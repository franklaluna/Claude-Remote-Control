// WebSocket 网关 — Agent 与 iOS 客户端双向消息中继（原生 WebSocket）
import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, WebSocket } from 'ws';
import { JwtService } from '@nestjs/jwt';
import { Logger } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { WsMessage, WsAuthPayload, WsMessageType } from '../types';

// Agent 连接池: device_id → WebSocket
const agentSockets = new Map<string, WebSocket>();
// iOS 客户端连接池: user_id → Set<WebSocket>
const clientSockets = new Map<string, Set<WebSocket>>();

@WebSocketGateway({ path: '/ws' })
export class WsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(WsGateway.name);

  constructor(
    private jwtService: JwtService,
    private prisma: PrismaService,
  ) {}

  // ---- 连接生命周期 ----

  handleConnection(ws: WebSocket) {
    this.logger.log('新 WebSocket 连接');
    const timer = setTimeout(() => {
      this.logger.warn('连接超时未认证，断开');
      ws.close(4001, '认证超时');
    }, 5000);

    ws.on('message', (raw: Buffer) => {
      let msg: WsMessage;
      try { msg = JSON.parse(raw.toString()); }
      catch { ws.close(4000, '无效 JSON'); return; }

      if (msg.type === 'auth') {
        this.handleAuth(ws, msg, timer);
        return;
      }

      if (!(ws as any)._userId) {
        ws.close(4001, '请先认证');
        return;
      }

      switch (msg.type) {
        case 'register_device': this.handleRegisterDevice(ws); break;
        case 'heartbeat': this.handleHeartbeat(ws, msg); break;
        case 'task_accepted': this.handleTaskAccepted(msg); break;
        case 'task_started': this.handleTaskStarted(msg); break;
        case 'task_log': this.handleTaskLog(msg); break;
        case 'task_progress': this.handleTaskProgress(msg); break;
        case 'file_changed': this.handleFileChanged(msg); break;
        case 'task_completed': this.handleTaskCompleted(msg); break;
        case 'task_failed': this.handleTaskFailed(msg); break;
        case 'cancel_task': this.handleCancelTask(ws, msg); break;
        case 'agent_offline': this.handleAgentOffline(ws); break;
      }
    });

    ws.on('close', () => { clearTimeout(timer); this.handleDisconnect(ws); });
    ws.on('error', (err) => { this.logger.warn(`WS error: ${err.message}`); });
  }

  handleDisconnect(ws: WebSocket) {
    for (const [deviceId, socket] of agentSockets) {
      if (socket === ws) {
        agentSockets.delete(deviceId);
        this.updateDeviceStatus(deviceId, 'offline');
        this.broadcastToUserByDevice(deviceId, buildMsg('device:offline', { device_id: deviceId, status: 'offline' }));
        this.logger.log(`Agent 断开: device=${deviceId}`);
        return;
      }
    }
    for (const [userId, sockets] of clientSockets) {
      if (sockets.has(ws)) { sockets.delete(ws); if (sockets.size === 0) clientSockets.delete(userId); return; }
    }
  }

  // ===== 认证 =====

  private async handleAuth(ws: WebSocket, msg: WsMessage, timer: NodeJS.Timeout) {
    const payload = msg.payload as WsAuthPayload;
    try {
      const decoded = this.jwtService.verify(payload.token);
      const userId: string = decoded.id;
      (ws as any)._userId = userId;
      clearTimeout(timer);

      if (payload.device_id) {
        const device = await this.prisma.device.findUnique({ where: { id: payload.device_id } });
        if (!device || device.user_id !== userId) {
          sendJson(ws, buildMsg('auth_error', { message: '设备不存在或无权访问' }));
          ws.close(); return;
        }
        (ws as any)._deviceId = payload.device_id;
        sendJson(ws, buildMsg('auth_ok', { message: '认证成功，请发送 register_device' }));
        this.logger.log(`Agent 已认证: device=${payload.device_id}`);
      } else {
        if (!clientSockets.has(userId)) clientSockets.set(userId, new Set());
        clientSockets.get(userId)!.add(ws);
        const devices = await this.prisma.device.findMany({ where: { user_id: userId } });
        for (const d of devices) {
          sendJson(ws, buildMsg('device:status', { device_id: d.id, status: d.status, name: d.name, platform: d.platform, last_seen: d.last_seen }));
        }
        sendJson(ws, buildMsg('auth_ok', { message: '客户端认证成功' }));
        this.logger.log(`iOS 客户端已认证: user=${userId}`);
      }
    } catch (err: any) {
      this.logger.warn(`认证失败: ${err.message}`);
      sendJson(ws, buildMsg('auth_error', { message: 'Token 无效或已过期' }));
      ws.close();
    }
  }

  // ===== 设备注册 =====

  private async handleRegisterDevice(ws: WebSocket) {
    const deviceId = (ws as any)._deviceId;
    if (!deviceId) { sendJson(ws, buildMsg('register_success', { status: 'error', message: '请先完成认证' })); return; }
    agentSockets.set(deviceId, ws);
    await this.updateDeviceStatus(deviceId, 'online');
    this.broadcastToUserByDevice(deviceId, buildMsg('device:online', { device_id: deviceId, status: 'online' }));
    sendJson(ws, buildMsg('register_success', { status: 'ok' }));
    await this.dispatchQueuedTasks(deviceId);
    this.logger.log(`设备已注册: device=${deviceId}`);
  }

  // ===== 心跳 =====

  private async handleHeartbeat(ws: WebSocket, msg: WsMessage) {
    const payload = msg.payload as { device_id?: string };
    if (payload.device_id) {
      await this.prisma.device.update({ where: { id: payload.device_id }, data: { last_seen: new Date() } }).catch(() => {});
    }
    sendJson(ws, buildMsg('heartbeat_ack', { timestamp: new Date().toISOString() }));
  }

  // ===== 任务事件 =====

  private async handleTaskAccepted(msg: WsMessage) {
    this.logger.log(`任务已确认: ${(msg.payload as any).task_id}`);
    await this.relayToTaskOwner((msg.payload as any).task_id, msg);
  }

  private async handleTaskStarted(msg: WsMessage) {
    const payload = msg.payload as { task_id: string };
    await this.prisma.task.update({ where: { id: payload.task_id }, data: { status: 'running' } }).catch(() => {});
    await this.relayToTaskOwner(payload.task_id, msg);
  }

  private async handleTaskLog(msg: WsMessage) {
    const payload = msg.payload as { task_id: string; message: string };
    await this.prisma.taskLog.create({ data: { task_id: payload.task_id, message: payload.message } }).catch(() => {});
    await this.relayToTaskOwner(payload.task_id, msg);
  }

  private async handleTaskProgress(msg: WsMessage) {
    await this.relayToTaskOwner((msg.payload as any).task_id, msg);
  }

  private async handleFileChanged(msg: WsMessage) {
    await this.relayToTaskOwner((msg.payload as any).task_id, msg);
  }

  private async handleTaskCompleted(msg: WsMessage) {
    const payload = msg.payload as { task_id: string; summary: string };
    await this.prisma.task.update({ where: { id: payload.task_id }, data: { status: 'completed', summary: payload.summary } }).catch(() => {});
    await this.relayToTaskOwner(payload.task_id, msg);
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) await this.dispatchQueuedTasks(task.device_id);
  }

  private async handleTaskFailed(msg: WsMessage) {
    const payload = msg.payload as { task_id: string; error: string };
    await this.prisma.task.update({ where: { id: payload.task_id }, data: { status: 'failed', error: payload.error } }).catch(() => {});
    await this.relayToTaskOwner(payload.task_id, msg);
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) await this.dispatchQueuedTasks(task.device_id);
  }

  private async handleCancelTask(ws: WebSocket, msg: WsMessage) {
    const payload = msg.payload as { task_id: string };
    const userId = (ws as any)._userId;
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (!task || task.user_id !== userId) return;
    if (task.status !== 'queued' && task.status !== 'running') return;

    await this.prisma.task.update({ where: { id: payload.task_id }, data: { status: 'cancelled' } });
    this.sendToDevice(task.device_id, buildMsg('cancel_task', { task_id: payload.task_id }));
    sendJson(ws, buildMsg('cancel_task', { task_id: payload.task_id, status: 'cancelled' }));
  }

  private async handleAgentOffline(ws: WebSocket) {
    const deviceId = (ws as any)._deviceId;
    if (deviceId) {
      agentSockets.delete(deviceId);
      await this.updateDeviceStatus(deviceId, 'offline');
      this.broadcastToUserByDevice(deviceId, buildMsg('device:offline', { device_id: deviceId, status: 'offline' }));
    }
    ws.close();
  }

  // ===== 公共方法 =====

  sendTaskCreate(deviceId: string, taskId: string, title: string, prompt: string, workingDirectory: string, timeoutMinutes?: number): boolean {
    const payload: any = { task_id: taskId, title, prompt, working_directory: workingDirectory };
    if (timeoutMinutes) payload.timeout_minutes = timeoutMinutes;
    return this.sendToDevice(deviceId, buildMsg('task_create', payload));
  }

  sendTaskContinue(deviceId: string, taskId: string, prompt: string, workingDirectory: string): boolean {
    return this.sendToDevice(deviceId, buildMsg('task_continue', { task_id: taskId, prompt, working_directory: workingDirectory }));
  }

  sendTaskCancel(deviceId: string, taskId: string): boolean {
    return this.sendToDevice(deviceId, buildMsg('cancel_task', { task_id: taskId }));
  }

  sendToDevice(deviceId: string, message: WsMessage): boolean {
    const socket = agentSockets.get(deviceId);
    if (!socket) return false;
    sendJson(socket, message);
    return true;
  }

  // ===== 私有方法 =====

  private async broadcastToUserByDevice(deviceId: string, message: WsMessage) {
    const device = await this.prisma.device.findUnique({ where: { id: deviceId } });
    if (!device) return;
    const sockets = clientSockets.get(device.user_id);
    if (!sockets) return;
    for (const s of sockets) sendJson(s, message);
  }

  private async relayToTaskOwner(taskId: string, message: WsMessage) {
    const task = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!task) return;
    const sockets = clientSockets.get(task.user_id);
    if (!sockets) return;
    for (const s of sockets) sendJson(s, message);
  }

  private async updateDeviceStatus(deviceId: string, status: 'online' | 'offline') {
    try {
      await this.prisma.device.update({ where: { id: deviceId }, data: { status, last_seen: new Date() } });
    } catch { this.logger.warn(`更新设备 ${deviceId} 状态失败`); }
  }

  private async dispatchQueuedTasks(deviceId: string) {
    const running = await this.prisma.task.findFirst({ where: { device_id: deviceId, status: 'running' } });
    if (running) return;

    const next = await this.prisma.task.findFirst({ where: { device_id: deviceId, status: 'queued' }, orderBy: { created_at: 'asc' } });
    if (!next) return;

    const sent = this.sendTaskCreate(deviceId, next.id, next.title, next.prompt, next.working_directory);
    if (!sent) return;

    await this.prisma.task.update({ where: { id: next.id }, data: { status: 'running' } });
    const socks = clientSockets.get(next.user_id);
    if (socks) {
      for (const s of socks) sendJson(s, buildMsg('task_started', { task_id: next.id }));
    }
    this.logger.log(`任务 ${next.id} 已派发给设备 ${deviceId}`);
  }
}

// ---- helpers ----

function buildMsg(type: WsMessageType, payload: unknown): WsMessage {
  return { type, payload, timestamp: new Date().toISOString() };
}

function sendJson(ws: WebSocket, msg: WsMessage) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}
