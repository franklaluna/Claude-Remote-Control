// Package ws 提供 Relay Server WebSocket 客户端连接管理
package ws

import (
	"encoding/json"
	"fmt"
	"log"
	"math"
	"math/rand"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Message WebSocket 统一消息格式
type Message struct {
	Type      string      `json:"type"`
	Payload   interface{} `json:"payload"`
	Timestamp string      `json:"timestamp"`
}

// AuthPayload 认证消息负载
type AuthPayload struct {
	Token    string `json:"token"`
	DeviceID string `json:"device_id"`
}

// HeartbeatPayload 心跳负载
type HeartbeatPayload struct {
	DeviceID string `json:"device_id"`
}

// CancelPayload 服务端取消任务负载
type CancelPayload struct {
	TaskID string `json:"task_id"`
}

// Client WebSocket 客户端
type Client struct {
	url      string
	conn     *websocket.Conn
	mu       sync.Mutex
	deviceID string
	token    string

	// 重连控制
	reconnect   bool
	reconnectCh chan struct{}
	maxBackoff  time.Duration

	// 消息接收回调
	OnTaskReceived   func(msg Message) // 新任务
	OnCancelReceived func(taskID string) // 取消任务
}

// NewClient 创建 WebSocket 客户端
func NewClient(serverURL, token, deviceID string) *Client {
	return &Client{
		url:         serverURL,
		token:       token,
		deviceID:    deviceID,
		reconnect:   true,
		reconnectCh: make(chan struct{}, 1),
		maxBackoff:  2 * time.Minute,
	}
}

// Connect 连接并认证，启动心跳和消息接收循环
func (c *Client) Connect() error {
	conn, _, err := websocket.DefaultDialer.Dial(c.url, nil)
	if err != nil {
		return fmt.Errorf("websocket 连接失败: %w", err)
	}
	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

	log.Printf("[ws] 已连接到 Relay Server: %s", c.url)

	// 发送认证
	if err := c.authenticate(); err != nil {
		conn.Close()
		return err
	}

	// 启动心跳
	go c.heartbeatLoop()

	return nil
}

// authenticate 发送认证消息并等待确认
func (c *Client) authenticate() error {
	msg := Message{
		Type: "auth",
		Payload: AuthPayload{
			Token:    c.token,
			DeviceID: c.deviceID,
		},
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
	}

	// 设置 5 秒认证超时
	c.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if err := c.conn.WriteJSON(msg); err != nil {
		return fmt.Errorf("发送认证消息失败: %w", err)
	}

	log.Printf("[ws] 已发送认证消息, device_id=%s", c.deviceID)

	// 读回认证响应
	_, resp, err := c.conn.ReadMessage()
	if err != nil {
		return fmt.Errorf("认证失败: %w", err)
	}
	c.conn.SetReadDeadline(time.Time{})

	// 解析响应确认认证成功
	var authResp struct {
		Type    string `json:"type"`
		Payload struct {
			Message string `json:"message"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(resp, &authResp); err == nil {
		if authResp.Type == "auth_error" {
			return fmt.Errorf("认证被拒绝: %s", authResp.Payload.Message)
		}
	}

	log.Printf("[ws] 认证成功")
	return nil
}

// Run 运行消息接收循环，支持自动重连
func (c *Client) Run() {
	for {
		if err := c.Connect(); err != nil {
			log.Printf("[ws] 连接失败: %v", err)
			if !c.reconnect {
				return
			}
			c.reconnectWithBackoff()
			continue
		}

		c.readLoop()

		if c.reconnect {
			c.reconnectWithBackoff()
		} else {
			return
		}
	}
}

// heartbeatLoop 每 30 秒发送心跳
func (c *Client) heartbeatLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		c.mu.Lock()
		conn := c.conn
		c.mu.Unlock()

		if conn == nil {
			return
		}

		msg := Message{
			Type: "heartbeat",
			Payload: HeartbeatPayload{
				DeviceID: c.deviceID,
			},
			Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		}

		c.mu.Lock()
		err := c.conn.WriteJSON(msg)
		c.mu.Unlock()
		if err != nil {
			log.Printf("[ws] 心跳发送失败: %v", err)
			return
		}
		log.Printf("[ws] 心跳已发送")
	}
}

// readLoop 持续读取服务端消息
func (c *Client) readLoop() {
	for {
		c.mu.Lock()
		conn := c.conn
		c.mu.Unlock()

		if conn == nil {
			return
		}

		var msg Message
		err := conn.ReadJSON(&msg)
		if err != nil {
			log.Printf("[ws] 读取消息失败: %v", err)
			return
		}

		log.Printf("[ws] 收到消息: type=%s", msg.Type)

		if msg.Type == "heartbeat_ack" {
			continue
		}

		// 处理取消消息
		if msg.Type == "cancel_task" {
			taskID := parseCancelPayload(msg.Payload)
			if taskID != "" {
				log.Printf("[ws] 收到取消任务: task_id=%s", taskID)
				if c.OnCancelReceived != nil {
					c.OnCancelReceived(taskID)
				}
			}
			continue
		}

		if c.OnTaskReceived != nil {
			c.OnTaskReceived(msg)
		}
	}
}

// parseCancelPayload 从消息负载中提取 task_id
func parseCancelPayload(payload interface{}) string {
	data, err := json.Marshal(payload)
	if err != nil {
		return ""
	}
	var cp CancelPayload
	if json.Unmarshal(data, &cp) != nil {
		return ""
	}
	return cp.TaskID
}

// reconnectWithBackoff 指数退避重连
func (c *Client) reconnectWithBackoff() {
	for attempt := 0; c.reconnect; attempt++ {
		backoff := time.Duration(math.Min(
			float64(time.Second)*math.Pow(2, float64(attempt)),
			float64(c.maxBackoff),
		))
		jitter := time.Duration(rand.Int63n(int64(backoff) / 2))
		wait := backoff - backoff/4 + jitter

		log.Printf("[ws] 第 %d 次重连等待 %v", attempt+1, wait)
		time.Sleep(wait)

		if err := c.Connect(); err == nil {
			return
		}
	}
}

// Send 发送消息到服务端
func (c *Client) Send(msg Message) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn == nil {
		return fmt.Errorf("websocket 未连接")
	}

	msg.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	return c.conn.WriteJSON(msg)
}

// Close 关闭连接
func (c *Client) Close() {
	c.reconnect = false
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}
}
