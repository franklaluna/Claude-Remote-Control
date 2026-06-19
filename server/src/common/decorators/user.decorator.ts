// 自定义参数装饰器 — 从请求中提取当前登录用户（由 JwtAuthGuard 注入）
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const User = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    return request.user;
  },
);
