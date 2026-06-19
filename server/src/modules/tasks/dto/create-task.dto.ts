// 创建任务请求 DTO
import { IsString, IsIn, MinLength, IsOptional } from 'class-validator';

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
}
