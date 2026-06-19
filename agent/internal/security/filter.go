// Package security 提供危险命令检测和过滤
// 使用正则匹配防止空格/制表符绕过，分类覆盖 35+ 危险模式
package security

import (
	"fmt"
	"regexp"
	"strings"
)

// rule 危险命令检测规则
type rule struct {
	Pattern *regexp.Regexp // 编译后的正则
	Label   string         // 人类可读的分类标签
}

// 分类黑名单 — 防止通过多余空格、制表符绕过
var rules = func() []rule {
	// 辅助: 匹配任意空白字符 (空格、制表符、换行等)
	sp := `[\s]+`

	patterns := []struct {
		pattern string
		label   string
	}{
		// === DestructiveFile: 破坏性文件操作 ===
		{`rm` + sp + `-rf` + sp + `/`, "DestructiveFile: rm -rf /"},
		{`rm` + sp + `-rf` + sp + `--no-preserve-root`, "DestructiveFile: rm -rf --no-preserve-root"},
		{`rm` + sp + `-rf` + sp + `~(?:/\*)?`, "DestructiveFile: rm -rf ~"},
		{`dd` + sp + `if=`, "DestructiveFile: dd 磁盘覆写"},
		{`mkfs\.`, "DestructiveFile: mkfs 格式化文件系统"},
		{`fdisk`, "DestructiveFile: fdisk 磁盘分区"},
		{`shred`, "DestructiveFile: shred 安全删除"},
		{`wipefs`, "DestructiveFile: wipefs 擦除文件系统"},
		{`mkswap`, "DestructiveFile: mkswap"},
		{`>\/dev\/sd[a-z]`, "DestructiveFile: 重定向覆写块设备"},
		{`>\/dev\/nvme`, "DestructiveFile: 重定向覆写 NVMe"},
		{`>\/dev\/mmcblk`, "DestructiveFile: 重定向覆写 MMC"},
		{`truncate` + sp + `-s` + sp + `0` + sp + `\/`, "DestructiveFile: truncate 清空文件"},
		{`cat` + sp + `\/dev\/null` + sp + `>`, "DestructiveFile: /dev/null 覆写"},
		{`chmod` + sp + `777` + sp + `\/`, "DestructiveFile: chmod 777 /"},
		{`chown` + sp + `-R` + sp + `root` + sp + `\/`, "DestructiveFile: chown -R root /"},
		{`mv` + sp + `\/`, "DestructiveFile: mv / 根目录移动"},
		{`dd` + sp + `bs=`, "DestructiveFile: dd bs= 块写入"},

		// === PrivilegeEscalation: 权限提升 ===
		{`sudo` + sp + `su`, "PrivilegeEscalation: sudo su"},
		{`sudo` + sp + `-i`, "PrivilegeEscalation: sudo -i"},
		{`passwd` + sp + `root`, "PrivilegeEscalation: passwd root"},
		{`chmod` + sp + `\+s` + sp + `\/`, "PrivilegeEscalation: chmod +s setuid"},
		{`usermod` + sp + `-aG` + sp + `sudo`, "PrivilegeEscalation: usermod sudo"},
		{`visudo`, "PrivilegeEscalation: visudo 编辑 sudoers"},

		// === ShellBypass: 代码执行/Shell 逃逸 ===
		{`:\(\)\s*\{` + sp + `:\|:&\s*\}` + sp + `;:`, "ShellBypass: fork bomb"},
		{`eval`, "ShellBypass: eval 动态执行"},
		{`exec\s*\(`, "ShellBypass: exec()"},
		{`system\s*\(`, "ShellBypass: system() 调用"},
		{`subprocess\.`, "ShellBypass: subprocess 调用"},
		{`os\.system`, "ShellBypass: os.system() Python 调用"},

		// === NetworkExfil: 网络外泄/反向Shell ===
		{`curl` + sp + `.*\|` + sp + `(?:ba)?sh`, "NetworkExfil: curl pipe to shell"},
		{`wget` + sp + `.*-O` + sp + `-` + sp + `\|`, "NetworkExfil: wget pipe to shell"},
		{`nc` + sp + `-e` + sp + `\/`, "NetworkExfil: nc -e 反向 shell"},
		{`\/dev\/tcp\/`, "NetworkExfil: /dev/tcp 反向 shell"},
		{`bash` + sp + `-i` + sp + `>&`, "NetworkExfil: bash -i 反向 shell"},
		{`python` + sp + `-c` + sp + `.*socket`, "NetworkExfil: Python 反向 shell"},

		// === SystemControl: 系统控制 ===
		{`shutdown`, "SystemControl: shutdown 关机"},
		{`reboot`, "SystemControl: reboot 重启"},
		{`halt`, "SystemControl: halt 停机"},
		{`poweroff`, "SystemControl: poweroff 断电"},
		{`systemctl` + sp + `(?:stop|disable|mask)` + sp + `sshd`, "SystemControl: 停止 SSH 服务"},
		{`init` + sp + `[06]`, "SystemControl: init 0/6 运行级别切换"},

		// === WindowsPowerShell: Windows 特定 ===
		{`Remove-Item` + sp + `-Recurse` + sp + `-Force` + sp + `[C-Z]:\\`, "WindowsPowerShell: Remove-Item 递归删除"},
		{`Format-Volume` + sp + `-DriveLetter`, "WindowsPowerShell: Format-Volume"},
		{`Stop-Computer`, "WindowsPowerShell: Stop-Computer"},
		{`Restart-Computer`, "WindowsPowerShell: Restart-Computer"},
		{`Clear-RecycleBin`, "WindowsPowerShell: Clear-RecycleBin"},
		{`Disable-WindowsOptionalFeature`, "WindowsPowerShell: 禁用系统功能"},
		{`Set-ExecutionPolicy` + sp + `Unrestricted`, "WindowsPowerShell: 降低执行策略"},
		{`net` + sp + `user` + sp + `administrator`, "WindowsPowerShell: net user administrator"},
	}

	result := make([]rule, 0, len(patterns))
	for _, p := range patterns {
		re := regexp.MustCompile(p.pattern)
		result = append(result, rule{
			Pattern: re,
			Label:   p.label,
		})
	}
	return result
}()

// Check 检测 prompt 是否包含危险命令
// 返回 safe=true 表示安全, safe=false 时 reason 说明原因
func Check(prompt string) (safe bool, reason string) {
	// 空格归一化: 把所有空白字符(空格、制表符、换行)替换为单个空格，防止空格绕过
	normalized := normalizeWhitespace(prompt)
	lower := strings.ToLower(normalized)

	for _, r := range rules {
		if r.Pattern.MatchString(lower) {
			return false, fmt.Sprintf("拒绝执行: 包含危险命令 [%s]", r.Label)
		}
	}
	return true, ""
}

// normalizeWhitespace 把所有连续空白字符归一化为单个空格
func normalizeWhitespace(s string) string {
	return regexp.MustCompile(`\s+`).ReplaceAllString(strings.TrimSpace(s), " ")
}
