import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class ContinueTaskDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(10000)
  prompt: string;
}
