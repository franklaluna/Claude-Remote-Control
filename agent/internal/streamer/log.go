// Package streamer 提供执行日志的实时流式上传
package streamer

import (
	"fmt"
	"sync"

	"github.com/claude-remote-control/agent/internal/ws"
)

// LogStreamer 日志流式上传器
type LogStreamer struct {
	client *ws.Client
	taskID string
	mu     sync.Mutex
	seq    int
}

// LogPayload 日志消息负载
type LogPayload struct {
	TaskID  string `json:"task_id"`
	Seq     int    `json:"seq"`
	Message string `json:"message"`
	IsError bool   `json:"is_error"`
}

// New 创建日志流式上传器
func New(client *ws.Client, taskID string) *LogStreamer {
	return &LogStreamer{
		client: client,
		taskID: taskID,
	}
}

// OnLine 实现 executor.LineHandler 签名，每收到一行日志即通过 WebSocket 上传
func (s *LogStreamer) OnLine(line string, isStderr bool) {
	s.mu.Lock()
	s.seq++
	seq := s.seq
	s.mu.Unlock()

	msg := ws.Message{
		Type: "task:log",
		Payload: LogPayload{
			TaskID:  s.taskID,
			Seq:     seq,
			Message: line,
			IsError: isStderr,
		},
	}

	if err := s.client.Send(msg); err != nil {
		fmt.Printf("[streamer] 日志上传失败 seq=%d: %v\n", seq, err)
	}
}
