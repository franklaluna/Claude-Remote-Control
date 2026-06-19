// Package result 负责收集执行结果并通过 WebSocket 发送
package result

import (
	"fmt"
	"strings"

	"github.com/claude-remote-control/agent/internal/executor"
	"github.com/claude-remote-control/agent/internal/ws"
)

// TaskCompletedPayload 任务完成负载
type TaskCompletedPayload struct {
	TaskID       string      `json:"task_id"`
	Summary      string      `json:"summary"`
	FilesChanged int         `json:"files_changed"`
	Files        []FileEntry `json:"files"`
}

// TaskFailedPayload 任务失败负载
type TaskFailedPayload struct {
	TaskID string `json:"task_id"`
	Error  string `json:"error"`
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
	if result.Error != nil || result.ExitCode != 0 {
		return c.sendFailed(result)
	}
	return c.sendCompleted(result)
}

// sendCompleted 发送任务完成消息
func (c *Collector) sendCompleted(result executor.Result) error {
	files := extractFiles(c.logs)
	payload := TaskCompletedPayload{
		TaskID:       c.taskID,
		Summary:      generateSummary(c.logs, len(files)),
		FilesChanged: len(files),
		Files:        files,
	}
	msg := ws.Message{Type: "task_completed", Payload: payload}

	fmt.Printf("[result] 任务完成: task_id=%s files_changed=%d\n", c.taskID, len(files))
	return c.client.Send(msg)
}

// sendFailed 发送任务失败消息
func (c *Collector) sendFailed(result executor.Result) error {
	var errStr string
	if result.Error != nil {
		errStr = result.Error.Error()
	} else {
		errStr = fmt.Sprintf("claude 退出码 %d", result.ExitCode)
	}
	payload := TaskFailedPayload{TaskID: c.taskID, Error: errStr}
	msg := ws.Message{Type: "task_failed", Payload: payload}

	fmt.Printf("[result] 任务失败: task_id=%s error=%s\n", c.taskID, extractShortError(errStr))
	return c.client.Send(msg)
}

// extractFiles 从日志行中提取文件路径变更
func extractFiles(logs []string) []FileEntry {
	seen := make(map[string]bool)
	var files []FileEntry

	for _, line := range logs {
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
