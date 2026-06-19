// ============================================================
// Shared Type Definitions — Claude Remote Control
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
  files: FileChangeEntry[];
  error?: string;
}

// --- WebSocket 消息类型 ---

export type WsMessageType =
  | 'task:new'
  | 'task:log'
  | 'task:status'
  | 'task:result'
  | 'device:status'
  | 'device:online'
  | 'device:offline'
  | 'heartbeat'
  | 'auth'
  | 'auth_ok'
  | 'auth_error'
  | 'heartbeat_ack';

export interface WsMessage {
  type: WsMessageType;
  payload: unknown;
  timestamp: string;
}

export interface WsTaskLogPayload {
  task_id: string;
  message: string;
}

export interface WsTaskStatusPayload {
  task_id: string;
  status: TaskStatus;
}

export interface WsTaskResultPayload {
  task_id: string;
  result: TaskResult;
}

export interface WsDeviceStatusPayload {
  device_id: string;
  status: 'online' | 'offline';
}

export interface WsAuthPayload {
  token: string;
  device_id: string;
}

export interface WsHeartbeatPayload {
  device_id: string;
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

// --- API 通用响应 ---

export interface ApiError {
  statusCode: number;
  message: string;
  error: string;
}
