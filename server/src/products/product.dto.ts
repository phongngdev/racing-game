import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsMongoId,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';

export class ProductInputDto {
  @ApiProperty({ example: 'Brushless ESC', minLength: 1, maxLength: 120 })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 120)
  name!: string;

  @ApiPropertyOptional({ example: 'Water-resistant electronic speed control.' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiProperty({ example: 59.99, minimum: 0 })
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(0)
  price!: number;

  @ApiPropertyOptional({
    type: String,
    nullable: true,
    example: '66c1a10d6b9a5e9a6a1c0123',
  })
  @IsOptional()
  @IsMongoId()
  categoryId?: string | null;
}

export class ProductDto {
  @ApiProperty({ example: '66c1a10d6b9a5e9a6a1c0123' })
  id!: string;

  @ApiProperty({ example: 'Brushless ESC' })
  name!: string;

  @ApiProperty({ example: 'Water-resistant electronic speed control.' })
  description!: string;

  @ApiProperty({ example: 59.99, minimum: 0 })
  price!: number;

  @ApiProperty({ type: String, nullable: true })
  categoryId!: string | null;

  @ApiProperty({ format: 'date-time' })
  createdAt!: Date;

  @ApiProperty({ format: 'date-time' })
  updatedAt!: Date;
}
