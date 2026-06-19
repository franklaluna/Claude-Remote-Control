// WebSocket 网关模块（全局）
import { Module, Global } from '@nestjs/common';
import { WsGateway } from './ws.gateway';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [WsGateway, PrismaService],
  exports: [WsGateway],
})
export class WsModule {}
