// 设备服务 — 设备 CRUD + 在线状态管理
import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateDeviceDto } from './dto/update-device.dto';
import { DeviceListResponse, Device } from '../../types';
import { WsGateway } from '../../common/ws.gateway';

@Injectable()
export class DevicesService {
  constructor(
    private prisma: PrismaService,
    private ws: WsGateway,
  ) {}

  /** 获取当前用户的设备列表 */
  async list(userId: string): Promise<DeviceListResponse> {
    const devices = await this.prisma.device.findMany({
      where: { user_id: userId },
      orderBy: { last_seen: 'desc' },
    });
    return { devices: devices as Device[] };
  }

  /** 注册新设备并返回注册凭证 */
  async create(userId: string, dto: CreateDeviceDto): Promise<{ device: Device }> {
    const device = await this.prisma.device.create({
      data: {
        user_id: userId,
        name: dto.name,
        platform: dto.platform,
        version: dto.version,
        status: 'offline',
      },
    });
    return { device: device as Device };
  }

  /** 重命名设备 */
  async update(userId: string, deviceId: string, dto: UpdateDeviceDto): Promise<{ device: Device }> {
    const device = await this.prisma.device.findUnique({ where: { id: deviceId } });
    if (!device) throw new NotFoundException('设备不存在');
    if (device.user_id !== userId) throw new ForbiddenException('无权操作该设备');

    const updated = await this.prisma.device.update({
      where: { id: deviceId },
      data: { name: dto.name },
    });
    return { device: updated as Device };
  }

  /** 删除设备及其关联任务 */
  async remove(userId: string, deviceId: string): Promise<{ message: string }> {
    const device = await this.prisma.device.findUnique({ where: { id: deviceId } });
    if (!device) throw new NotFoundException('设备不存在');
    if (device.user_id !== userId) throw new ForbiddenException('无权操作该设备');

    await this.prisma.device.delete({ where: { id: deviceId } });
    return { message: '设备已删除' };
  }

  /** 更新设备在线状态（由 WebSocket 网关调用） */
  async setOnlineStatus(deviceId: string, status: 'online' | 'offline'): Promise<void> {
    await this.prisma.device.update({
      where: { id: deviceId },
      data: {
        status,
        last_seen: new Date(),
      },
    });
  }
}
