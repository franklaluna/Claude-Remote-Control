// 登录请求 DTO — class-validator 校验
import { IsEmail, IsString, MinLength } from 'class-validator';

export class LoginDto {
  @IsEmail({}, { message: '邮箱格式不正确' })
  email!: string;

  @IsString()
  @MinLength(6, { message: '密码至少6位' })
  password!: string;
}
