// NestJS Relay Server — 入口（原生 WebSocket）
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { WsAdapter } from '@nestjs/platform-ws';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // 使用原生 WebSocket 适配器（兼容 iOS 原生 WebSocket 客户端）
  app.useWebSocketAdapter(new WsAdapter(app));

  // 全局 API 前缀
  app.setGlobalPrefix('api');

  // 请求体校验管道
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // CORS
  const corsOrigin = process.env.CORS_ORIGIN;
  if (corsOrigin) {
    app.enableCors({
      origin: corsOrigin === '*' ? '*' : corsOrigin.split(',').map((s) => s.trim()),
      credentials: true,
    });
  }

  const port = process.env.PORT || 3000;
  // 强制 IPv4 绑定（0.0.0.0），解决某些网络环境下 dual-stack 问题
  await app.listen(port, '0.0.0.0');
  console.log(`Relay Server running on port ${port} (IPv4)${corsOrigin ? ' (CORS: ' + corsOrigin + ')' : ''}`);
}

bootstrap();
