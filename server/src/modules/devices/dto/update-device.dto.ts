// 更新设备请求 DTO（重命名）
import { IsString, MinLength, IsOptional } from 'class-validator';

export class UpdateDeviceDto {
  @IsOptional()
  @IsString()
  @MinLength(1, { message: '设备名称不能为空' })
  name?: string;
}
