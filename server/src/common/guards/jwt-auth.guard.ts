// JWT 认证守卫 — 验证 Bearer Token 并将用户信息注入 request.user
import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

export interface JwtPayload {
  id: string;
  email: string;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private jwtService: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('未提供认证 Token');
    }

    const token = authHeader.slice(7);
    try {
      const payload = this.jwtService.verify<JwtPayload>(token);
      request.user = { id: payload.id, email: payload.email };
      return true;
    } catch {
      throw new UnauthorizedException('Token 无效或已过期');
    }
  }
}
