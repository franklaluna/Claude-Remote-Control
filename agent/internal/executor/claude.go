// Package executor 提供 Claude Code CLI 子进程启动和管理
package executor

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os/exec"
	"runtime"
)

// RunMode Claude 执行模式
type RunMode string

const (
	ModeDefault RunMode = "claude"         // 交互模式
	ModePrint   RunMode = "claude --print" // 纯输出模式 (非交互)
)

// Task 待执行的任务
type Task struct {
	TaskID           string
	Prompt           string
	WorkingDirectory string
	PermissionMode   string
}

// Result Claude 执行结果
type Result struct {
	TaskID   string
	ExitCode int
	Error    error
}

// LineHandler 逐行输出回调
type LineHandler func(line string, isStderr bool)

// Claude CLI 执行器封装
type Claude struct {
	claudePath string
}

// New 创建 Claude 执行器，自动检测 claude CLI 路径
func New() *Claude {
	return &Claude{
		claudePath: detectClaudePath(),
	}
}

// IsInstalled 检查 claude CLI 是否已安装
func (c *Claude) IsInstalled() bool {
	return c.claudePath != ""
}

// Path 返回检测到的 claude 路径
func (c *Claude) Path() string {
	return c.claudePath
}

// Execute 启动 claude 子进程并实时捕获输出
// ctx 可用于超时控制或外部取消（ctx.Done() 时发送 SIGKILL 终止子进程）
// onLine 每行输出时回调
func (c *Claude) Execute(ctx context.Context, task Task, onLine LineHandler) Result {
	if c.claudePath == "" {
		return Result{
			TaskID: task.TaskID,
			Error:  fmt.Errorf("claude CLI 未安装，请在 PATH 中安装 claude"),
		}
	}

	// 构建命令参数
	args := buildArgs(task)
	cmd := exec.CommandContext(ctx, c.claudePath, args...)
	cmd.Dir = task.WorkingDirectory

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return Result{TaskID: task.TaskID, ExitCode: -1, Error: fmt.Errorf("创建 stdout pipe 失败: %w", err)}
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return Result{TaskID: task.TaskID, ExitCode: -1, Error: fmt.Errorf("创建 stderr pipe 失败: %w", err)}
	}

	fmt.Printf("[executor] 启动 claude: %s %v (chdir=%s)\n", c.claudePath, args, task.WorkingDirectory)

	if err := cmd.Start(); err != nil {
		return Result{TaskID: task.TaskID, ExitCode: -1, Error: fmt.Errorf("启动 claude 进程失败: %w", err)}
	}

	// 并行读取 stdout 和 stderr
	done := make(chan struct{})
	go streamLines(stdout, false, onLine, done)
	go streamLines(stderr, true, onLine, done)

	// 监听 ctx.Done() 以便在外部取消时优雅终止
	waitDone := make(chan error, 1)
	go func() {
		// 等待两个流都读完
		<-done
		<-done
		waitDone <- cmd.Wait()
	}()

	var waitErr error
	select {
	case <-ctx.Done():
		// 上下文被取消（超时或外部取消）—— cmd 已被 CommandContext 自动 kill
		fmt.Printf("[executor] 任务被取消: task_id=%s reason=%v\n", task.TaskID, ctx.Err())
		waitErr = ctx.Err()
	case waitErr = <-waitDone:
		// 正常完成
	}

	exitCode := 0
	if waitErr != nil {
		if ctx.Err() != nil {
			exitCode = -1
		} else if exitErr, ok := waitErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
	}

	fmt.Printf("[executor] claude 执行完成: exit_code=%d\n", exitCode)

	return Result{
		TaskID:   task.TaskID,
		ExitCode: exitCode,
		Error:    waitErr,
	}
}

// streamLines 逐行读取 Reader 并回调
func streamLines(r io.Reader, isStderr bool, onLine LineHandler, done chan<- struct{}) {
	defer func() { done <- struct{}{} }()
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024) // 1MB 行缓冲
	for scanner.Scan() {
		if onLine != nil {
			onLine(scanner.Text(), isStderr)
		}
	}
}

// buildArgs 根据任务配置构建 claude 命令行参数
func buildArgs(task Task) []string {
	var args []string

	// 判断是 --print 模式还是交互模式
	args = append(args, "--print")

	// 传递 prompt
	args = append(args, task.Prompt)

	// 权限模式映射
	switch task.PermissionMode {
	case "bypassPermissions":
		args = append(args, "--dangerously-skip-permissions")
	case "acceptEdits":
		args = append(args, "--permission-mode", "acceptEdits")
	case "plan":
		args = append(args, "--permission-mode", "plan")
	}

	return args
}

// detectClaudePath 检测系统上可用的 claude CLI 路径
func detectClaudePath() string {
	// 首先尝试 PATH 中的 claude
	if path, err := exec.LookPath("claude"); err == nil {
		return path
	}

	// Windows 常见安装路径
	if runtime.GOOS == "windows" {
		candidates := []string{
			`C:\Program Files\Claude\claude.exe`,
			`C:\Users\%USERPROFILE%\AppData\Local\Programs\Claude\claude.exe`,
		}
		for _, p := range candidates {
			if _, err := exec.LookPath(p); err == nil {
				return p
			}
		}
	}

	return ""
}
