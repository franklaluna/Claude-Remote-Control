# API Contracts — Claude Remote Control

> Relay Server 对外 API 契约文档
> 版本: 1.0.0
> 基路径: `/api`

---

## 认证

所有 API 端点（除 `/api/auth/login` 外）均需在请求头中携带 JWT:

```
Authorization: Bearer <token>
```

---

## REST 端点

### POST /api/auth/login

用户登录，获取 JWT token。

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response 200:**
```json
{
  "token": "eyJhbGciOi...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "created_at": "2026-06-19T00:00:00Z"
  }
}
```

**Response 401:**
```json
{
  "statusCode": 401,
  "message": "邮箱或密码错误",
  "error": "Unauthorized"
}
```

---

### GET /api/devices

获取当前用户的所有注册设备。

**Response 200:**
```json
{
  "devices": [
    {
      "id": "device-uuid",
      "user_id": "user-uuid",
      "name": "MacBook Pro",
      "platform": "macos",
      "status": "online",
      "version": "1.0.0",
      "last_seen": "2026-06-19T10:00:00Z",
      "created_at": "2026-06-19T08:00:00Z"
    }
  ]
}
```

---

### POST /api/devices

注册新设备。

**Request Body:**
```json
{
  "name": "MacBook Pro",
  "platform": "macos",
  "version": "1.0.0"
}
```

**Response 201:**
```json
{
  "device": {
    "id": "device-uuid",
    "user_id": "user-uuid",
    "name": "MacBook Pro",
    "platform": "macos",
    "status": "offline",
    "version": "1.0.0",
    "last_seen": "2026-06-19T08:00:00Z",
    "created_at": "2026-06-19T08:00:00Z"
  }
}
```

---

### DELETE /api/devices/:id

删除设备及其关联任务。

**Response 200:**
```json
{
  "message": "设备已删除"
}
```

---

### GET /api/tasks

获取当前用户的任务列表。

**Query Parameters:**
| 参数     | 类型   | 必填 | 说明                                  |
|----------|--------|------|---------------------------------------|
| status   | string | 否   | 按状态过滤 (queued/running/completed/failed/cancelled) |
| device_id | string | 否   | 按设备过滤                            |
| limit    | number | 否   | 返回数量限制 (默认20)                 |
| offset   | number | 否   | 分页偏移 (默认0)                      |

**Response 200:**
```json
{
  "tasks": [
    {
      "id": "task-uuid",
      "user_id": "user-uuid",
      "device_id": "device-uuid",
      "title": "Refactor Auth",
      "prompt": "Refactor authentication module...",
      "working_directory": "/Users/dev/project",
      "permission_mode": "default",
      "status": "completed",
      "created_at": "2026-06-19T09:00:00Z",
      "updated_at": "2026-06-19T09:05:00Z"
    }
  ]
}
```

---

### POST /api/tasks

创建新任务并推送到目标设备的队列。

**Request Body:**
```json
{
  "title": "Refactor Auth Module",
  "prompt": "Refactor authentication module with JWT middleware",
  "device_id": "device-uuid",
  "working_directory": "/Users/dev/project",
  "permission_mode": "default"
}
```

**Response 201:**
```json
{
  "task": {
    "id": "task-uuid",
    "user_id": "user-uuid",
    "device_id": "device-uuid",
    "title": "Refactor Auth Module",
    "prompt": "Refactor authentication module with JWT middleware",
    "working_directory": "/Users/dev/project",
    "permission_mode": "default",
    "status": "queued",
    "created_at": "2026-06-19T09:00:00Z",
    "updated_at": "2026-06-19T09:00:00Z"
  }
}
```

**Response 400:**
```json
{
  "statusCode": 400,
  "message": "目标设备不在线",
  "error": "Bad Request"
}
```

---

### GET /api/tasks/:id

获取任务详情，含执行日志和结果。

**Response 200:**
```json
{
  "task": {
    "id": "task-uuid",
    "status": "completed",
    "...": "..."
  },
  "logs": [
    {
      "id": "log-uuid",
      "task_id": "task-uuid",
      "timestamp": "2026-06-19T09:01:00Z",
      "message": "Analyzing repository..."
    }
  ],
  "result": {
    "status": "completed",
    "summary": "Authentication module updated",
    "files_changed": 5,
    "files": [
      { "path": "src/auth.ts" },
      { "path": "src/middleware.ts" }
    ]
  }
}
```

---

### POST /api/tasks/:id/cancel

取消排队中的任务。

**Response 200:**
```json
{
  "task": {
    "id": "task-uuid",
    "status": "cancelled",
    "...": "..."
  }
}
```

**Response 400:**
```json
{
  "statusCode": 400,
  "message": "只能取消排队中的任务",
  "error": "Bad Request"
}
```

---

## WebSocket 协议

### 连接端点
```
wss://<host>/ws
```

### 连接认证

连接后必须首先发送认证消息，否则 5 秒内未认证将断开连接。

```json
{
  "type": "auth",
  "payload": {
    "token": "eyJhbGciOi...",
    "device_id": "device-uuid"
  },
  "timestamp": "2026-06-19T10:00:00Z"
}
```

### 消息格式

所有 WebSocket 消息统一使用以下格式:

```json
{
  "type": "<message_type>",
  "payload": { "...": "..." },
  "timestamp": "2026-06-19T10:00:00.000Z"
}
```

### 消息类型

| Type             | 方向              | 说明                   |
|------------------|-------------------|------------------------|
| `auth`           | Client → Server   | 连接认证               |
| `heartbeat`      | 双向              | 心跳保活 (30s 间隔)    |
| `task:log`       | Agent → Server → iOS | 任务执行日志           |
| `task:status`    | Agent → Server → iOS | 任务状态变更           |
| `task:result`    | Agent → Server → iOS | 任务执行结果           |
| `device:status`  | Server → iOS      | 设备上下线通知         |
| `device:online`  | Agent → Server → iOS | 设备上线              |
| `device:offline` | Server → iOS      | 设备离线 (心跳超时)    |

### 心跳机制

- 客户端和 Agent 每 30 秒发送一次 `heartbeat`
- 服务端 90 秒未收到心跳视为离线
- 服务端收到心跳回复 `heartbeat` 确认

### iOS 客户端接收示例

**任务日志推送:**
```json
{
  "type": "task:log",
  "payload": {
    "task_id": "task-uuid",
    "message": "Running tests..."
  },
  "timestamp": "2026-06-19T09:01:05.000Z"
}
```

**设备上线通知:**
```json
{
  "type": "device:online",
  "payload": {
    "device_id": "device-uuid"
  },
  "timestamp": "2026-06-19T10:00:00.000Z"
}
```
