// 创建设备请求 DTO
import { IsString, IsIn, MinLength } from 'class-validator';

export class CreateDeviceDto {
  @IsString()
  @MinLength(1, { message: '设备名称不能为空' })
  name!: string;

  @IsString()
  @IsIn(['macos', 'windows'], { message: '平台必须是 macos 或 windows' })
  platform!: 'macos' | 'windows';

  @IsString()
  version!: string;
}
