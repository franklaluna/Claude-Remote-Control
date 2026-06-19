// 任务控制器 — GET/POST/POST:cancel /api/tasks
import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { TasksService } from './tasks.service';
import { JwtAuthGuard, JwtPayload } from '../../common/guards/jwt-auth.guard';
import { User } from '../../common/decorators/user.decorator';
import { CreateTaskDto } from './dto/create-task.dto';
import {
  CreateTaskResponse,
  GetTaskResponse,
  TaskListResponse,
  CancelTaskResponse,
} from '../../types';

@Controller('tasks')
@UseGuards(JwtAuthGuard)
export class TasksController {
  constructor(private readonly tasksService: TasksService) {}

  @Get()
  async list(
    @User() user: JwtPayload,
    @Query('status') status?: string,
    @Query('device_id') deviceId?: string,
    @Query('limit') limit?: number,
    @Query('offset') offset?: number,
  ): Promise<TaskListResponse> {
    return this.tasksService.list(user.id, { status, deviceId, limit, offset });
  }

  @Post()
  async create(
    @User() user: JwtPayload,
    @Body() body: CreateTaskDto,
  ): Promise<CreateTaskResponse> {
    return this.tasksService.create(user.id, body);
  }

  @Get(':id')
  async get(
    @User() user: JwtPayload,
    @Param('id') id: string,
  ): Promise<GetTaskResponse> {
    return this.tasksService.get(user.id, id);
  }

  @Post(':id/cancel')
  async cancel(
    @User() user: JwtPayload,
    @Param('id') id: string,
  ): Promise<CancelTaskResponse> {
    return this.tasksService.cancel(user.id, id);
  }
}
