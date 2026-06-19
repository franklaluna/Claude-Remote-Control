// 根模块 — 组装所有业务模块
import { Module } from '@nestjs/common';
import { AuthModule } from './modules/auth/auth.module';
import { DevicesModule } from './modules/devices/devices.module';
import { TasksModule } from './modules/tasks/tasks.module';
import { NotificationModule } from './modules/notification/notification.module';
import { WsModule } from './common/ws.module';
import { PrismaService } from './common/prisma.service';

@Module({
  imports: [AuthModule, DevicesModule, TasksModule, NotificationModule, WsModule],
  providers: [PrismaService],
  exports: [PrismaService],
})
export class AppModule {}
