// 任务服务 — 任务 CRUD + FIFO 队列 + WebSocket 调度
import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';
import { WsGateway } from '../../common/ws.gateway';
import { CreateTaskDto } from './dto/create-task.dto';
import {
  Task,
  TaskLog,
  TaskResult,
  CreateTaskResponse,
  GetTaskResponse,
  TaskListResponse,
  CancelTaskResponse,
  DeleteTaskResponse,
} from '../../types';

@Injectable()
export class TasksService {
  private readonly logger = new Logger(TasksService.name);

  constructor(
    private prisma: PrismaService,
    private ws: WsGateway,
  ) {}

  /** 任务列表（支持按状态过滤、分页） */
  async list(
    userId: string,
    filters: { status?: string; deviceId?: string; limit?: number; offset?: number },
  ): Promise<TaskListResponse> {
    const where: Record<string, unknown> = { user_id: userId };
    if (filters.status) where.status = filters.status;
    if (filters.deviceId) where.device_id = filters.deviceId;

    const tasks = await this.prisma.task.findMany({
      where,
      take: filters.limit || 20,
      skip: filters.offset || 0,
      orderBy: { created_at: 'desc' },
    });

    return { tasks: tasks as Task[] };
  }

  /** 创建任务并尝试调度 */
  async create(userId: string, dto: CreateTaskDto): Promise<CreateTaskResponse> {
    // 验证设备属于该用户
    const device = await this.prisma.device.findUnique({ where: { id: dto.device_id } });
    if (!device || device.user_id !== userId) {
      throw new BadRequestException('设备不存在或无权访问');
    }

    const task = await this.prisma.task.create({
      data: {
        user_id: userId,
        device_id: dto.device_id,
        title: dto.title,
        prompt: dto.prompt,
        working_directory: dto.working_directory || '',
        permission_mode: dto.permission_mode || 'default',
        status: 'queued',
      },
    });

    // 任务创建后立即尝试调度（如果设备在线且无运行中任务则立即派发）
    await this.tryDispatchNext(dto.device_id);

    return { task: task as Task };
  }

  /** 获取任务详情（含日志和结果） */
  async get(userId: string, taskId: string): Promise<GetTaskResponse> {
    const task = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!task || task.user_id !== userId) {
      throw new NotFoundException('任务不存在');
    }

    const logs = await this.prisma.taskLog.findMany({
      where: { task_id: taskId },
      orderBy: { timestamp: 'asc' },
    });

    const result: GetTaskResponse = {
      task: task as Task,
      logs: logs as TaskLog[],
    };

    // 已完成/失败的任务附带结果摘要
    if (task.status === 'completed' || task.status === 'failed') {
      const files: { path: string }[] = []; // 文件变更由 Agent Service 上报后存储
      result.result = {
        status: task.status as 'completed' | 'failed',
        summary: task.summary || '',
        files_changed: 0,
        files,
        ...(task.error ? { error: task.error } : {}),
      };
    }

    return result;
  }

  /** 取消排队中或运行中的任务 */
  async cancel(userId: string, taskId: string): Promise<CancelTaskResponse> {
    const task = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!task || task.user_id !== userId) {
      throw new NotFoundException('任务不存在');
    }
    if (task.status !== 'queued' && task.status !== 'running') {
      throw new BadRequestException('只能取消排队中或运行中的任务');
    }

    // 运行中的任务：先通过 WebSocket 向 Agent 发送取消指令
    if (task.status === 'running') {
      this.ws.sendTaskCancel(task.device_id, taskId);
    }

    const updated = await this.prisma.task.update({
      where: { id: taskId },
      data: { status: 'cancelled' },
    });

    return { task: updated as Task };
  }

  /** 追加日志条目（由 WebSocket 网关调用） */
  async appendLog(taskId: string, message: string): Promise<void> {
    await this.prisma.taskLog.create({
      data: { task_id: taskId, message },
    });
  }

  /** 更新任务状态（由 WebSocket 网关调用） */
  async updateStatus(
    taskId: string,
    status: string,
    extra?: { summary?: string; error?: string },
  ): Promise<void> {
    const data: Record<string, unknown> = { status };
    if (extra?.summary) data.summary = extra.summary;
    if (extra?.error) data.error = extra.error;

    const task = await this.prisma.task.update({
      where: { id: taskId },
      data,
    });

    // 任务结束 (completed/failed/cancelled) → 尝试调度该设备下一个排队任务
    if (status === 'completed' || status === 'failed' || status === 'cancelled') {
      await this.tryDispatchNext(task.device_id);
    }
  }

  /** 在当前任务基础上继续对话（复用同一任务，发送追问到 Agent） */
  async continueTask(userId: string, parentTaskId: string, followUpPrompt: string): Promise<CreateTaskResponse> {
    const parent = await this.prisma.task.findUnique({ where: { id: parentTaskId } });
    if (!parent || parent.user_id !== userId) {
      throw new NotFoundException('任务不存在');
    }
    if (parent.status === 'queued' || parent.status === 'running' || parent.status === 'cancelled') {
      throw new BadRequestException('无法继续排队中、运行中或已取消的任务');
    }

    // 追加追问日志
    await this.appendLog(parentTaskId, `追问: ${followUpPrompt}`);

    // 将任务状态重置为 running
    const updated = await this.prisma.task.update({
      where: { id: parentTaskId },
      data: { status: 'running' },
    });

    // 通过 WebSocket 发送追问指令到 Agent
    this.ws.sendTaskContinue(parent.device_id, parentTaskId, followUpPrompt, parent.working_directory);
    this.logger.log(`追问已发送: task=${parentTaskId}, device=${parent.device_id}`);

    return { task: updated as Task };
  }

  /** 删除已完成/失败/取消的任务 */
  async delete(userId: string, taskId: string): Promise<DeleteTaskResponse> {
    const task = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!task || task.user_id !== userId) {
      throw new NotFoundException('任务不存在');
    }
    if (task.status !== 'completed' && task.status !== 'failed' && task.status !== 'cancelled') {
      throw new BadRequestException('只能删除已完成、失败或取消的任务');
    }

    await this.prisma.task.delete({ where: { id: taskId } });
    return { ok: true };
  }

  // ---- 内部方法 ----

  /** FIFO 调度：取出设备上最早排队任务，若设备在线则派发 */
  private async tryDispatchNext(deviceId: string): Promise<void> {
    // 检查是否已有正在运行的任务
    const running = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'running' },
    });
    if (running) return; // 设备正忙

    // 取最早排队的任务
    const next = await this.prisma.task.findFirst({
      where: { device_id: deviceId, status: 'queued' },
      orderBy: { created_at: 'asc' },
    });
    if (!next) return; // 无排队任务

    // 通过 WebSocket 向 Agent 推送任务
    const sent = this.ws.sendTaskCreate(
      deviceId,
      next.id,
      next.title,
      next.prompt,
      next.working_directory,
      (next as any).timeout_minutes,
    );

    if (sent) {
      // Agent 在线，任务转为 running
      await this.prisma.task.update({
        where: { id: next.id },
        data: { status: 'running' },
      });
      this.logger.log(`任务 ${next.id} 已派发给设备 ${deviceId}`);
    }
    // Agent 离线 → 任务保持 queued，等待 Agent 上线后重试
  }
}
