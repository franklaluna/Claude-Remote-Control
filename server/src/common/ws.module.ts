// WebSocket 网关模块（全局，原生 WebSocket）
import { Module, Global } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { WsGateway } from './ws.gateway';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  imports: [
    JwtModule.register({
      secret: process.env.JWT_SECRET || 'dev-secret',
      signOptions: { expiresIn: process.env.JWT_EXPIRES_IN || '7d' },
    }),
  ],
  providers: [WsGateway, PrismaService],
  exports: [WsGateway],
})
export class WsModule {}
