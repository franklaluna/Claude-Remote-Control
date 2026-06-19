// 设备控制器 — GET/POST/PATCH/DELETE /api/devices
import { Controller, Get, Post, Patch, Delete, Param, Body, UseGuards } from '@nestjs/common';
import { DevicesService } from './devices.service';
import { JwtAuthGuard, JwtPayload } from '../../common/guards/jwt-auth.guard';
import { User } from '../../common/decorators/user.decorator';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateDeviceDto } from './dto/update-device.dto';
import { DeviceListResponse } from '../../types';

@Controller('devices')
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Get()
  async list(@User() user: JwtPayload): Promise<DeviceListResponse> {
    return this.devicesService.list(user.id);
  }

  @Post()
  async create(
    @User() user: JwtPayload,
    @Body() body: CreateDeviceDto,
  ): Promise<{ device: import('../../types').Device }> {
    return this.devicesService.create(user.id, body);
  }

  @Patch(':id')
  async update(
    @User() user: JwtPayload,
    @Param('id') id: string,
    @Body() body: UpdateDeviceDto,
  ): Promise<{ device: import('../../types').Device }> {
    return this.devicesService.update(user.id, id, body);
  }

  @Delete(':id')
  async remove(
    @User() user: JwtPayload,
    @Param('id') id: string,
  ): Promise<{ message: string }> {
    return this.devicesService.remove(user.id, id);
  }
}
