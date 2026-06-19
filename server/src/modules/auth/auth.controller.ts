// 认证控制器 — POST /api/auth/login, POST /api/auth/register
import { Controller, Post, Body } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { LoginResponse } from '../../types';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  async login(@Body() body: LoginDto): Promise<LoginResponse> {
    return this.authService.login(body);
  }

  @Post('register')
  async register(@Body() body: RegisterDto): Promise<LoginResponse> {
    return this.authService.register(body);
  }
}
