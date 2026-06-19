// Package task 提供任务接收和解析
package task

import (
	"encoding/json"
	"fmt"

	"github.com/claude-remote-control/agent/internal/ws"
)

// TaskParams 服务端下发的任务参数
type TaskParams struct {
	TaskID           string `json:"task_id"`
	Title            string `json:"title"`
	Prompt           string `json:"prompt"`
	WorkingDirectory string `json:"working_directory"`
	PermissionMode   string `json:"permission_mode"`
}

// Receiver 任务接收器
type Receiver struct {
	OnTask func(params TaskParams)
}

// NewReceiver 创建任务接收器
func NewReceiver(onTask func(params TaskParams)) *Receiver {
	return &Receiver{OnTask: onTask}
}

// Handle 处理 WebSocket 消息，解析任务下发
func (r *Receiver) Handle(msg ws.Message) {
	if msg.Type != "task_create" {
		return
	}

	params, err := parseTaskPayload(msg.Payload)
	if err != nil {
		fmt.Printf("[task] 任务解析失败: %v\n", err)
		return
	}

	fmt.Printf("[task] 收到新任务: id=%s title=%s\n", params.TaskID, params.Title)

	if r.OnTask != nil {
		r.OnTask(params)
	}
}

// parseTaskPayload 从 WebSocket 消息 payload 解析任务参数
func parseTaskPayload(payload interface{}) (TaskParams, error) {
	var params TaskParams

	data, err := json.Marshal(payload)
	if err != nil {
		return params, fmt.Errorf("序列化 payload 失败: %w", err)
	}

	if err := json.Unmarshal(data, &params); err != nil {
		return params, fmt.Errorf("反序列化任务参数失败: %w", err)
	}

	if params.TaskID == "" {
		return params, fmt.Errorf("缺少 task_id")
	}
	if params.Prompt == "" {
		return params, fmt.Errorf("缺少 prompt")
	}

	if params.PermissionMode == "" {
		params.PermissionMode = "default"
	}
	if params.WorkingDirectory == "" {
		params.WorkingDirectory = "."
	}

	return params, nil
}

// AckPayload ACK 确认消息负载
type AckPayload struct {
	TaskID string `json:"task_id"`
	Status string `json:"status"` // "accepted" | "rejected"
	Reason string `json:"reason,omitempty"`
}

// NewAcceptedMessage 创建任务接收确认消息
func NewAcceptedMessage(taskID string) ws.Message {
	return ws.Message{
		Type: "task_accepted",
		Payload: AckPayload{
			TaskID: taskID,
			Status: "accepted",
		},
	}
}

// NewRejectedMessage 创建任务拒绝消息
func NewRejectedMessage(taskID, reason string) ws.Message {
	return ws.Message{
		Type: "task_accepted",
		Payload: AckPayload{
			TaskID: taskID,
			Status: "rejected",
			Reason: reason,
		},
	}
}
