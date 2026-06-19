// WebSocket 网关 — Agent 与 iOS 客户端双向消息中继
// 消息类型对齐 AGENT_PROTOCOL.md v1.0

import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
import { Logger } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import {
  WsMessage,
  WsAuthPayload,
  WsTaskLogPayload,
  WsTaskProgressPayload,
  WsFileChangedPayload,
  WsTaskCompletedPayload,
  WsTaskFailedPayload,
  WsTaskAcceptedPayload,
  WsTaskStartedPayload,
  WsCancelTaskPayload,
  WsHeartbeatPayload,
} from '../types';

// Agent 连接池: device_id → Socket
const agentSockets = new Map<string, Socket>();
// iOS 客户端连接池: user_id → Set<Socket>
const clientSockets = new Map<string, Set<Socket>>();

@WebSocketGateway({
  cors: { origin: '*' },
  path: '/ws',
  pingInterval: 25000,
  pingTimeout: 60000,
})
export class WsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(WsGateway.name);
  private pendingAuth = new Map<string, NodeJS.Timeout>();

  constructor(
    private jwtService: JwtService,
    private prisma: PrismaService,
  ) {}

  // ---- 连接生命周期 ----

  handleConnection(client: Socket) {
    this.logger.log(`新连接: ${client.id}`);
    this.pendingAuth.set(
      client.id,
      setTimeout(() => {
        this.logger.warn(`连接 ${client.id} 超时未认证，断开`);
        client.disconnect();
        this.pendingAuth.delete(client.id);
      }, 5000),
    );
  }

  handleDisconnect(client: Socket) {
    clearTimeout(this.pendingAuth.get(client.id));
    this.pendingAuth.delete(client.id);

    // 从 Agent 池移除 → 标记设备离线
    for (const [deviceId, socket] of agentSockets) {
      if (socket.id === client.id) {
        agentSockets.delete(deviceId);
        this.updateDeviceStatus(deviceId, 'offline');
        this.broadcastToUserByDevice(deviceId, {
          type: 'device:offline',
          payload: { device_id: deviceId, status: 'offline' },
          timestamp: new Date().toISOString(),
        });
        this.logger.log(`Agent 断开: device=${deviceId}`);
        return;
      }
    }

    // 从 iOS 客户端池移除
    for (const [userId, sockets] of clientSockets) {
      if (sockets.has(client)) {
        sockets.delete(client);
        if (sockets.size === 0) clientSockets.delete(userId);
        return;
      }
    }
  }

  // ===================================================================
  // 认证
  // ===================================================================

  @SubscribeMessage('auth')
  async handleAuth(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsAuthPayload;

    try {
      // BLOCK-4: 真实 JWT 验证
      const decoded = this.jwtService.verify(payload.token);
      const userId: string = decoded.id;

      clearTimeout(this.pendingAuth.get(client.id));
      this.pendingAuth.delete(client.id);

      // 存入 socket.data 供后续消息使用
      (client as any)._userId = userId;

      if (payload.device_id) {
        // Agent 连接 → 验证设备归属
        const device = await this.prisma.device.findUnique({
          where: { id: payload.device_id },
        });
        if (!device || device.user_id !== userId) {
          client.emit('auth_error', { message: '设备不存在或无权访问' });
          client.disconnect();
          return;
        }

        (client as any)._deviceId = payload.device_id;
        client.emit('auth_ok', { message: '认证成功，请发送 register_device' });
        this.logger.log(`Agent 已认证: device=${payload.device_id}`);
      } else {
        // iOS 客户端 → 注册到客户端池
        if (!clientSockets.has(userId)) {
          clientSockets.set(userId, new Set());
        }
        clientSockets.get(userId)!.add(client);

        // 推送当前设备状态
        const devices = await this.prisma.device.findMany({
          where: { user_id: userId },
        });
        for (const d of devices) {
          client.emit('device:status', {
            type: 'device:status',
            payload: {
              device_id: d.id,
              status: d.status,
              name: d.name,
              platform: d.platform,
              last_seen: d.last_seen,
            },
            timestamp: new Date().toISOString(),
          });
        }

        client.emit('auth_ok', { message: '客户端认证成功' });
        this.logger.log(`iOS 客户端已认证: user=${userId}`);
      }
    } catch (err: any) {
      this.logger.warn(`认证失败: ${err.message}`);
      client.emit('auth_error', { message: 'Token 无效或已过期' });
      client.disconnect();
    }
  }

  // ===================================================================
  // 设备注册（Agent 初始化，按协议在 auth 之后调用）
  // ===================================================================

  @SubscribeMessage('register_device')
  async handleRegisterDevice(client: Socket, raw: string | WsMessage) {
    const deviceId = (client as any)._deviceId;
    if (!deviceId) {
      client.emit('register_success', { status: 'error', message: '请先完成认证' });
      return;
    }

    // 注册到 Agent 连接池
    agentSockets.set(deviceId, client);
    await this.updateDeviceStatus(deviceId, 'online');

    // 广播设备上线
    this.broadcastToUserByDevice(deviceId, {
      type: 'device:online',
      payload: { device_id: deviceId, status: 'online' },
      timestamp: new Date().toISOString(),
    });

    client.emit('register_success', { status: 'ok' });

    // 上线后检查并派发排队任务
    await this.dispatchQueuedTasks(deviceId);
    this.logger.log(`设备已注册: device=${deviceId}`);
  }

  // ===================================================================
  // 心跳（含系统指标）
  // ===================================================================

  @SubscribeMessage('heartbeat')
  async handleHeartbeat(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsHeartbeatPayload;

    if (payload.device_id) {
      await this.prisma.device.update({
        where: { id: payload.device_id },
        data: { last_seen: new Date() },
      }).catch(() => {});
    }
    client.emit('heartbeat_ack', { timestamp: new Date().toISOString() });
  }

  // ===================================================================
  // 任务确认与启动（Agent → Server）
  // ===================================================================

  @SubscribeMessage('task_accepted')
  async handleTaskAccepted(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskAcceptedPayload;
    this.logger.log(`任务已确认: ${payload.task_id}`);
    await this.relayToTaskOwner(payload.task_id, message);
  }

  @SubscribeMessage('task_started')
  async handleTaskStarted(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskStartedPayload;

    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: { status: 'running' },
    }).catch(() => {});

    await this.relayToTaskOwner(payload.task_id, message);
  }

  // ===================================================================
  // 任务执行流（Agent → Server → iOS）
  // ===================================================================

  @SubscribeMessage('task_log')
  async handleTaskLog(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskLogPayload;

    // 持久化
    await this.prisma.taskLog.create({
      data: { task_id: payload.task_id, message: payload.message },
    }).catch(() => {});

    await this.relayToTaskOwner(payload.task_id, message);
  }

  @SubscribeMessage('task_progress')
  async handleTaskProgress(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    await this.relayToTaskOwner(
      (message.payload as WsTaskProgressPayload).task_id,
      message,
    );
  }

  @SubscribeMessage('file_changed')
  async handleFileChanged(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    await this.relayToTaskOwner(
      (message.payload as WsFileChangedPayload).task_id,
      message,
    );
  }

  // ===================================================================
  // 任务完成/失败（Agent → Server）
  // ===================================================================

  @SubscribeMessage('task_completed')
  async handleTaskCompleted(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskCompletedPayload;

    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: {
        status: 'completed',
        summary: payload.summary,
      },
    }).catch(() => {});

    await this.relayToTaskOwner(payload.task_id, message);

    // 调度下一个排队任务
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) await this.dispatchQueuedTasks(task.device_id);
  }

  @SubscribeMessage('task_failed')
  async handleTaskFailed(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskFailedPayload;

    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: { status: 'failed', error: payload.error },
    }).catch(() => {});

    await this.relayToTaskOwner(payload.task_id, message);

    // 调度下一个排队任务
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) await this.dispatchQueuedTasks(task.device_id);
  }

  // ===================================================================
  // 取消任务（iOS → Server）
  // ===================================================================

  @SubscribeMessage('cancel_task')
  async handleCancelTask(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsCancelTaskPayload;
    const userId = (client as any)._userId;

    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (!task || task.user_id !== userId) return;

    if (task.status !== 'queued') return; // 只能取消排队任务

    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: { status: 'cancelled' },
    });

    // 通知 Agent 取消（如果已派发）
    this.sendToDevice(task.device_id, {
      type: 'cancel_task',
      payload: { task_id: payload.task_id },
      timestamp: new Date().toISOString(),
    });

    client.emit('cancel_task', {
      type: 'cancel_task',
      payload: { task_id: payload.task_id, status: 'cancelled' },
      timestamp: new Date().toISOString(),
    });
  }

  // ===================================================================
  // Agent 离线通知
  // ===================================================================

  @SubscribeMessage('agent_offline')
  async handleAgentOffline(client: Socket, raw: string | WsMessage) {
    const deviceId = (client as any)._deviceId;
    if (deviceId) {
      agentSockets.delete(deviceId);
      await this.updateDeviceStatus(deviceId, 'offline');
      this.broadcastToUserByDevice(deviceId, {
        type: 'device:offline',
        payload: { device_id: deviceId, status: 'offline' },
        timestamp: new Date().toISOString(),
      });
    }
    client.disconnect();
  }

  // ===================================================================
  // 公共方法（供 REST API / TasksService 调用）
  // ===================================================================

  /** 向指定设备的 Agent 推送任务创建消息 */
  sendTaskCreate(deviceId: string, taskId: string, title: string, prompt: string, workingDirectory: string): boolean {
    return this.sendToDevice(deviceId, {
      type: 'task_create',
      payload: { task_id: taskId, title, prompt, working_directory: workingDirectory },
      timestamp: new Date().toISOString(),
    });
  }

  /** 向指定设备的 Agent 发送消息 */
  sendToDevice(deviceId: string, message: WsMessage): boolean {
    const socket = agentSockets.get(deviceId);
    if (!socket) return false;
    socket.emit(message.type, message);
    return true;
  }

  // ===================================================================
  // 私有方法
  // ===================================================================

  /** 向指定设备的所属用户的所有 iOS 客户端广播 */
  private async broadcastToUserByDevice(deviceId: string, message: WsMessage) {
    const device = await this.prisma.device.findUnique({ where: { id: deviceId } });
    if (!device) return;
    const sockets = clientSockets.get(device.user_id);
    if (!sockets) return;
    for (const socket of sockets) socket.emit(message.type, message);
  }

  /** 向任务所属用户广播 */
  private async relayToTaskOwner(taskId: string, message: WsMessage) {
    const task = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!task) return;
    const sockets = clientSockets.get(task.user_id);
    if (!sockets) return;
    for (const socket of sockets) socket.emit(message.type, message);
  }

  /** 更新设备在线状态 */
  private async updateDeviceStatus(deviceId: string, status: 'online' | 'offline') {
    try {
      await this.prisma.device.update({
        where: { id: deviceId },
        data: { status, last_seen: new Date() },
      });
    } catch {
      this.logger.warn(`更新设备 ${deviceId} 状态失败`);
    }
  }

  /** Agent 上线/任务结束后调度排队任务 */
  private async dispatchQueuedTasks(deviceId: string) {
    const running = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'running' },
    });
    if (running) return;

    const next = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'queued' },
      orderBy: { created_at: 'asc' },
    });
    if (!next) return;

    const sent = this.sendTaskCreate(
      deviceId,
      next.id,
      next.title,
      next.prompt,
      next.working_directory,
    );

    if (sent) {
      await this.prisma.task.update({
        where: { id: next.id },
        data: { status: 'running' },
      });

      const socks = clientSockets.get(next.user_id);
      if (socks) {
        for (const s of socks) {
          s.emit('task_started', {
            type: 'task_started',
            payload: { task_id: next.id },
            timestamp: new Date().toISOString(),
          });
        }
      }
      this.logger.log(`任务 ${next.id} 已派发给设备 ${deviceId}`);
    }
  }
}
