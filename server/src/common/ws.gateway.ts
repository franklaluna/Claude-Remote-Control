// WebSocket 网关 — Agent 与 iOS 客户端双向消息中继
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
import { TasksService } from '../modules/tasks/tasks.service';
import { DevicesService } from '../modules/devices/devices.service';
import {
  WsMessage,
  WsAuthPayload,
  WsTaskLogPayload,
  WsTaskStatusPayload,
  WsTaskResultPayload,
} from '../types';

// 连接池: device_id → Socket（Agent 连接）
const agentSockets = new Map<string, Socket>();
// 连接池: user_id → Set<Socket>（iOS 客户端连接）
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
    this.logger.log(`新连接: ${client.id} (transport: ${client.conn.transport.name})`);
    // 必须在 5 秒内发送 auth 消息进行认证
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

    // 从 Agent 池移除
    for (const [deviceId, socket] of agentSockets) {
      if (socket.id === client.id) {
        agentSockets.delete(deviceId);
        this.updateDeviceStatus(deviceId, 'offline');
        this.broadcastToUserClients(deviceId, {
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
        this.logger.log(`iOS 客户端断开: user=${userId}`);
        return;
      }
    }
  }

  // ---- 认证 ----

  @SubscribeMessage('auth')
  async handleAuth(client: Socket, raw: string | WsMessage) {
    // socket.io 客户端可能发送 JSON 字符串或已解析的对象
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsAuthPayload;

    try {
      // 验证 JWT
      const decoded = this.jwtService.verify(payload.token);
      const userId: string = decoded.id;

      clearTimeout(this.pendingAuth.get(client.id));
      this.pendingAuth.delete(client.id);

      if (payload.device_id) {
        // Agent 连接 — 验证设备归属
        const device = await this.prisma.device.findUnique({
          where: { id: payload.device_id },
        });
        if (!device || device.user_id !== userId) {
          this.logger.warn(`Agent 认证失败: device=${payload.device_id}`);
          client.emit('auth_error', { message: '设备不存在或无权访问' });
          client.disconnect();
          return;
        }

        // 注册 Agent 连接
        agentSockets.set(payload.device_id, client);
        await this.updateDeviceStatus(payload.device_id, 'online');

        // 广播设备上线
        this.broadcastToUserClients(payload.device_id, {
          type: 'device:online',
          payload: { device_id: payload.device_id, status: 'online' },
          timestamp: new Date().toISOString(),
        });

        // 上线后检查是否有排队任务需要派发
        await this.dispatchQueuedTasks(payload.device_id);

        client.emit('auth_ok', { message: 'Agent 认证成功' });
        this.logger.log(`Agent 已认证: device=${payload.device_id}`);
      } else {
        // iOS 客户端连接 — 按 user_id 注册
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

  // ---- 心跳 ----

  @SubscribeMessage('heartbeat')
  async handleHeartbeat(client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as { device_id?: string };

    if (payload.device_id) {
      // 更新最后在线时间
      await this.prisma.device.update({
        where: { id: payload.device_id },
        data: { last_seen: new Date() },
      });
    }
    client.emit('heartbeat_ack', { timestamp: new Date().toISOString() });
  }

  // ---- 任务日志转发 ----

  @SubscribeMessage('task:log')
  async handleTaskLog(_client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskLogPayload;

    // 持久化日志
    await this.prisma.taskLog.create({
      data: {
        task_id: payload.task_id,
        message: payload.message,
      },
    });

    // 转发给 iOS 客户端
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) {
      this.broadcastToUserClientsById(task.user_id, message);
    }
  }

  // ---- 任务状态转发 ----

  @SubscribeMessage('task:status')
  async handleTaskStatus(_client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskStatusPayload;

    // 更新任务状态
    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: { status: payload.status },
    });

    // 转发给 iOS 客户端
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) {
      this.broadcastToUserClientsById(task.user_id, message);

      // 任务结束 → 调度下一个排队任务
      if (payload.status === 'completed' || payload.status === 'failed') {
        await this.dispatchQueuedTasks(task.device_id);
      }
    }
  }

  // ---- 任务结果接收 ----

  @SubscribeMessage('task:result')
  async handleTaskResult(_client: Socket, raw: string | WsMessage) {
    const message: WsMessage = typeof raw === 'string' ? JSON.parse(raw) : raw;
    const payload = message.payload as WsTaskResultPayload;

    // 更新任务结果
    await this.prisma.task.update({
      where: { id: payload.task_id },
      data: {
        status: payload.result.status,
        summary: payload.result.summary || null,
        error: payload.result.error || null,
      },
    });

    // 转发给 iOS 客户端
    const task = await this.prisma.task.findUnique({ where: { id: payload.task_id } });
    if (task) {
      this.broadcastToUserClientsById(task.user_id, message);

      // 调度下一个排队任务
      await this.dispatchQueuedTasks(task.device_id);
    }
  }

  // ---- 公共方法（供 REST API 调用） ----

  /** 向指定设备的 Agent 发送消息 */
  sendToDevice(deviceId: string, message: WsMessage): boolean {
    const socket = agentSockets.get(deviceId);
    if (!socket) return false;
    socket.emit(message.type, message);
    return true;
  }

  /** 向指定用户的所有 iOS 客户端广播 */
  broadcastToUser(userId: string, message: WsMessage) {
    const sockets = clientSockets.get(userId);
    if (!sockets) return;
    for (const socket of sockets) {
      socket.emit(message.type, message);
    }
  }

  // ---- 私有方法 ----

  /** 向设备对应的用户广播（需查询设备归属） */
  private async broadcastToUserClients(deviceId: string, message: WsMessage) {
    const device = await this.prisma.device.findUnique({ where: { id: deviceId } });
    if (!device) return;
    this.broadcastToUserClientsById(device.user_id, message);
  }

  /** 向指定 userId 的所有 iOS 客户端广播 */
  private broadcastToUserClientsById(userId: string, message: WsMessage) {
    const sockets = clientSockets.get(userId);
    if (!sockets) return;
    for (const socket of sockets) {
      socket.emit(message.type, message);
    }
  }

  /** 更新设备在线状态并广播 */
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

  /** Agent 上线后调度排队任务 */
  private async dispatchQueuedTasks(deviceId: string) {
    // 检查是否已有运行中任务
    const running = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'running' },
    });
    if (running) return;

    const next = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'queued' },
      orderBy: { created_at: 'asc' },
    });
    if (!next) return;

    const sent = this.sendToDevice(deviceId, {
      type: 'task:new',
      payload: {
        task_id: next.id,
        title: next.title,
        prompt: next.prompt,
        working_directory: next.working_directory,
        permission_mode: next.permission_mode,
      },
      timestamp: new Date().toISOString(),
    });

    if (sent) {
      await this.prisma.task.update({
        where: { id: next.id },
        data: { status: 'running' },
      });
      this.broadcastToUserClientsById(next.user_id, {
        type: 'task:status',
        payload: { task_id: next.id, status: 'running' },
        timestamp: new Date().toISOString(),
      });
      this.logger.log(`任务 ${next.id} 已派发给 ${deviceId}`);
    }
  }
}
