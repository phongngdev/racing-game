import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class GoogleLoginDto {
  @ApiProperty({ maxLength: 8192 })
  @IsString()
  @Length(20, 8192)
  idToken!: string;

  @ApiPropertyOptional({ minLength: 8, maxLength: 128, format: 'password' })
  @IsOptional()
  @IsString()
  @Length(8, 128)
  @MaxLength(128)
  linkPassword?: string;
}
