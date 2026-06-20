// ============================================================
// Shared Type Definitions — Claude Remote Control
// 消息类型对齐 AGENT_PROTOCOL.md v1.0
// ============================================================

// --- Domain Entities ---

/** 用户账号 */
export interface User {
  id: string;
  email: string;
  password_hash: string;
  created_at: Date;
}

/** 注册设备（macOS/Windows） */
export interface Device {
  id: string;
  user_id: string;
  name: string;
  platform: 'macos' | 'windows';
  status: 'online' | 'offline';
  version: string;
  last_seen: Date;
  created_at: Date;
}

/** 任务状态枚举 */
export type TaskStatus = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled';

/** 权限模式 */
export type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';

/** 用户创建的 Claude Code 执行任务 */
export interface Task {
  id: string;
  user_id: string;
  device_id: string;
  title: string;
  prompt: string;
  working_directory: string;
  permission_mode: PermissionMode;
  status: TaskStatus;
  summary?: string;
  error?: string;
  created_at: Date;
  updated_at: Date;
}

/** 任务执行日志条目 */
export interface TaskLog {
  id: string;
  task_id: string;
  timestamp: Date;
  message: string;
}

/** 任务完成后的文件变更摘要 */
export interface FileChangeEntry {
  path: string;
}

export interface TaskResult {
  status: 'completed' | 'failed';
  summary: string;
  files_changed: number;
  duration_seconds?: number;
  files: FileChangeEntry[];
  error?: string;
}

// --- WebSocket 消息类型（对齐 AGENT_PROTOCOL.md） ---

/** Agent ↔ Server 协议消息 */
export type WsMessageType =
  // 认证与注册
  | 'auth'
  | 'auth_ok'
  | 'auth_error'
  | 'register_device'
  | 'register_success'
  // 心跳
  | 'heartbeat'
  | 'heartbeat_ack'
  // 任务生命周期（Server → Agent）
  | 'task_create'
  | 'task_continue'
  // 任务生命周期（Agent → Server）
  | 'task_accepted'
  | 'task_started'
  | 'task_completed'
  | 'task_failed'
  // 执行流（Agent → Server → iOS）
  | 'task_log'
  | 'task_progress'
  | 'file_changed'
  // iOS → Server
  | 'cancel_task'
  // 设备状态（Server → iOS，协议扩展）
  | 'device:status'
  | 'device:online'
  | 'device:offline'
  // Agent 生命周期
  | 'agent_offline';

/** 通用消息信封 */
export interface WsMessage {
  type: WsMessageType;
  payload: unknown;
  timestamp: string;
}

// --- 认证与注册 Payload ---

export interface WsAuthPayload {
  token: string;
  device_id?: string; // Agent 连接时提供
}

export interface WsRegisterDevicePayload {
  device_id: string;
  name: string;
  platform: 'macos' | 'windows';
  agent_version: string;
}

// --- 心跳 Payload ---

export interface WsHeartbeatPayload {
  device_id: string;
  cpu?: number;
  memory?: number;
  active_task?: boolean;
}

// --- Server → Agent: 创建任务 ---

export interface WsTaskCreatePayload {
  task_id: string;
  title: string;
  prompt: string;
  working_directory: string;
  timeout_minutes?: number;
}

// --- Server → Agent: 追问当前任务 ---

export interface WsTaskContinuePayload {
  task_id: string;
  prompt: string;
  working_directory: string;
}

// --- Agent → Server: 任务确认 ---

export interface WsTaskAcceptedPayload {
  task_id: string;
}

export interface WsTaskStartedPayload {
  task_id: string;
}

// --- Agent → Server: 任务日志 ---

export interface WsTaskLogPayload {
  task_id: string;
  message: string;
}

// --- Agent → Server: 任务进度 ---

export interface WsTaskProgressPayload {
  task_id: string;
  percent: number;
}

// --- Agent → Server: 文件变更 ---

export interface WsFileChangedPayload {
  task_id: string;
  file: string;
}

// --- Agent → Server: 任务完成 ---

export interface WsTaskCompletedPayload {
  task_id: string;
  summary: string;
  files_changed: number;
  duration_seconds?: number;
}

// --- Agent → Server: 任务失败 ---

export interface WsTaskFailedPayload {
  task_id: string;
  error: string;
}

// --- iOS → Server: 取消任务 ---

export interface WsCancelTaskPayload {
  task_id: string;
}

// --- Server → iOS: 设备状态 ---

export interface WsDeviceStatusPayload {
  device_id: string;
  status: 'online' | 'offline';
  name?: string;
  platform?: string;
  last_seen?: Date;
}

// --- API 请求/响应类型 ---

/** POST /api/auth/login */
export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  user: Omit<User, 'password_hash'>;
}

/** GET /api/devices */
export interface DeviceListResponse {
  devices: Device[];
}

/** POST /api/devices */
export interface CreateDeviceRequest {
  name: string;
  platform: 'macos' | 'windows';
  version: string;
}

export interface CreateDeviceResponse {
  device: Device;
}

/** POST /api/tasks */
export interface CreateTaskRequest {
  title: string;
  prompt: string;
  device_id: string;
  working_directory: string;
  permission_mode: PermissionMode;
}

export interface CreateTaskResponse {
  task: Task;
}

/** GET /api/tasks/:id */
export interface GetTaskResponse {
  task: Task;
  logs: TaskLog[];
  result?: TaskResult;
}

/** POST /api/tasks/:id/cancel */
export interface CancelTaskResponse {
  task: Task;
}

/** GET /api/tasks */
export interface TaskListResponse {
  tasks: Task[];
}

/** DELETE /api/tasks/:id */
export interface DeleteTaskResponse {
  ok: boolean;
}

// --- API 通用响应 ---

export interface ApiError {
  statusCode: number;
  message: string;
  error: string;
}
