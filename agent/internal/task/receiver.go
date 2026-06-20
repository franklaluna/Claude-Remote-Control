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
	TimeoutMinutes   int    `json:"timeout_minutes"`
}

// TaskContinueParams 继续任务参数（同一会话追加提问）
type TaskContinueParams struct {
	TaskID           string `json:"task_id"`
	Prompt           string `json:"prompt"`
	WorkingDirectory string `json:"working_directory"`
}

// Receiver 任务接收器
type Receiver struct {
	OnTask     func(params TaskParams)
	OnContinue func(params TaskContinueParams)
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
	if params.TimeoutMinutes <= 0 {
		params.TimeoutMinutes = 30
	}

	return params, nil
}

// HandleContinue 处理 task_continue 消息类型
func (r *Receiver) HandleContinue(msg ws.Message) {
	if msg.Type != "task_continue" {
		return
	}

	params, err := parseContinuePayload(msg.Payload)
	if err != nil {
		fmt.Printf("[task] task_continue 解析失败: %v\n", err)
		return
	}

	fmt.Printf("[task] 收到追问: task_id=%s prompt=%.80s\n", params.TaskID, params.Prompt)

	if r.OnContinue != nil {
		r.OnContinue(params)
	}
}

// parseContinuePayload 解析 task_continue 消息负载
func parseContinuePayload(payload interface{}) (TaskContinueParams, error) {
	var params TaskContinueParams

	data, err := json.Marshal(payload)
	if err != nil {
		return params, fmt.Errorf("序列化 payload 失败: %w", err)
	}

	if err := json.Unmarshal(data, &params); err != nil {
		return params, fmt.Errorf("反序列化继续任务参数失败: %w", err)
	}

	if params.TaskID == "" {
		return params, fmt.Errorf("缺少 task_id")
	}
	if params.Prompt == "" {
		return params, fmt.Errorf("缺少 prompt")
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
