// 创建任务请求 DTO
import { IsString, IsIn, IsInt, Min, Max, MinLength, IsOptional } from 'class-validator';

export class CreateTaskDto {
  @IsString()
  @MinLength(1, { message: '任务标题不能为空' })
  title!: string;

  @IsString()
  @MinLength(1, { message: '任务提示不能为空' })
  prompt!: string;

  @IsString()
  device_id!: string;

  @IsOptional()
  @IsString()
  working_directory?: string;

  @IsOptional()
  @IsString()
  @IsIn(['default', 'acceptEdits', 'bypassPermissions', 'plan'], {
    message: '无效的权限模式',
  })
  permission_mode?: string;

  @IsOptional()
  @IsInt({ message: '超时分钟数必须是整数' })
  @Min(5, { message: '超时分钟数不能小于5' })
  @Max(120, { message: '超时分钟数不能大于120' })
  timeout_minutes?: number;
}
