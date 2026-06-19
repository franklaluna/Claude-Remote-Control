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

  // CORS（仅当显式配置 CORS_ORIGIN 时启用，生产环境默认拒绝跨域）
  const corsOrigin = process.env.CORS_ORIGIN;
  if (corsOrigin) {
    app.enableCors({
      origin: corsOrigin === '*' ? '*' : corsOrigin.split(',').map((s) => s.trim()),
      credentials: true,
    });
  }

  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`Relay Server running on port ${port}${corsOrigin ? ' (CORS: ' + corsOrigin + ')' : ' (CORS disabled)'}`);
}

bootstrap();
