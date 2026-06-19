// Package result 负责收集执行结果并通过 WebSocket 发送
package result

import (
	"fmt"
	"strings"

	"github.com/claude-remote-control/agent/internal/executor"
	"github.com/claude-remote-control/agent/internal/ws"
)

// TaskResultPayload 任务最终结果负载
type TaskResultPayload struct {
	TaskID       string        `json:"task_id"`
	Status       string        `json:"status"` // "completed" | "failed"
	ExitCode     int           `json:"exit_code"`
	Summary      string        `json:"summary"`
	FilesChanged int           `json:"files_changed"`
	Files        []FileEntry   `json:"files"`
	Error        string        `json:"error,omitempty"`
}

// FileEntry 文件变更条目
type FileEntry struct {
	Path string `json:"path"`
}

// Collector 结果收集器
type Collector struct {
	client *ws.Client
	taskID string
	logs   []string
}

// NewCollector 创建结果收集器
func NewCollector(client *ws.Client, taskID string) *Collector {
	return &Collector{
		client: client,
		taskID: taskID,
	}
}

// CollectLog 收集一条日志（用于摘要生成）
func (c *Collector) CollectLog(line string) {
	c.logs = append(c.logs, line)
}

// Send 收集 claude 执行结果并发送到服务端
func (c *Collector) Send(result executor.Result) error {
	payload := c.buildResult(result)
	msg := ws.Message{
		Type:    "task:result",
		Payload: payload,
	}

	fmt.Printf("[result] 发送最终结果: task_id=%s status=%s exit_code=%d\n",
		c.taskID, payload.Status, result.ExitCode)

	return c.client.Send(msg)
}

// buildResult 根据 executor.Result 构建结果负载
func (c *Collector) buildResult(result executor.Result) TaskResultPayload {
	payload := TaskResultPayload{
		TaskID:   c.taskID,
		ExitCode: result.ExitCode,
		Files:    []FileEntry{},
	}

	if result.Error != nil {
		payload.Status = "failed"
		payload.Error = result.Error.Error()
		payload.Summary = "执行失败: " + extractShortError(result.Error.Error())
		return payload
	}

	if result.ExitCode != 0 {
		payload.Status = "failed"
		payload.Error = fmt.Sprintf("claude 退出码 %d", result.ExitCode)
		payload.Summary = fmt.Sprintf("执行异常退出 (exit_code=%d)", result.ExitCode)
		return payload
	}

	// 从日志中提取文件变更信息
	files := extractFiles(c.logs)
	payload.Status = "completed"
	payload.FilesChanged = len(files)
	payload.Files = files
	payload.Summary = generateSummary(c.logs, len(files))

	return payload
}

// extractFiles 从日志行中提取文件路径变更
func extractFiles(logs []string) []FileEntry {
	seen := make(map[string]bool)
	var files []FileEntry

	for _, line := range logs {
		// 匹配 Claude CLI 输出的文件变更格式
		// 常见模式: "Writing src/file.ts", "Modified src/file.ts", "Reading src/file.ts"
		for _, prefix := range []string{"Writing ", "Modified ", "Created ", "Reading "} {
			if strings.HasPrefix(line, prefix) {
				path := strings.TrimPrefix(line, prefix)
				path = strings.TrimSpace(path)
				if path != "" && !seen[path] {
					seen[path] = true
					files = append(files, FileEntry{Path: path})
				}
				break
			}
		}
	}
	return files
}

// generateSummary 根据日志生成执行摘要
func generateSummary(logs []string, filesChanged int) string {
	if filesChanged > 0 {
		return fmt.Sprintf("任务执行完成，共修改 %d 个文件", filesChanged)
	}
	// 取最后几行有意义的日志作为摘要
	for i := len(logs) - 1; i >= 0; i-- {
		line := strings.TrimSpace(logs[i])
		if line != "" && !strings.HasPrefix(line, "[") {
			return fmt.Sprintf("任务执行完成: %.200s", line)
		}
	}
	return "任务执行完成"
}

// extractShortError 提取错误信息的前 200 字符
func extractShortError(errStr string) string {
	if len(errStr) > 200 {
		return errStr[:200] + "..."
	}
	return errStr
}
