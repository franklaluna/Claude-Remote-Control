// NestJS Relay Server — 入口

import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

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
