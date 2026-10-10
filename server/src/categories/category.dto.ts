import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, Length, MaxLength, ValidateIf } from 'class-validator';

export class CategoryInputDto {
  @ApiProperty({ example: 'Accessories', minLength: 1, maxLength: 100 })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 100)
  name!: string;

  @ApiPropertyOptional({ example: 'Optional racing accessories.' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(2000)
  description?: string;
}

export class CategoryDto {
  @ApiProperty({ example: '66c1a10d6b9a5e9a6a1c0123' })
  id!: string;

  @ApiProperty({ example: 'Accessories' })
  name!: string;

  @ApiProperty({ example: 'Optional racing accessories.' })
  description!: string;

  @ApiProperty({ format: 'date-time' })
  createdAt!: Date;

  @ApiProperty({ format: 'date-time' })
  updatedAt!: Date;
}
