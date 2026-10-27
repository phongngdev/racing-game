import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsInt,
  IsNumber,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import {
  RaceHistoryEndReason,
  RaceHistoryMode,
  RaceHistoryPlayerStatus,
  RaceHistorySlot,
} from './race-history.schema.js';

export class RaceHistoryPlayerInputDto {
  @ApiProperty({ enum: RaceHistorySlot })
  @IsEnum(RaceHistorySlot)
  slot!: RaceHistorySlot;

  @ApiProperty({ enum: ['red', 'blue'] })
  @IsEnum(['red', 'blue'])
  vehicle!: 'red' | 'blue';

  @ApiProperty({ enum: ['phone', 'keyboard'] })
  @IsEnum(['phone', 'keyboard'])
  source!: 'phone' | 'keyboard';

  @ApiProperty({ enum: RaceHistoryPlayerStatus })
  @IsEnum(RaceHistoryPlayerStatus)
  status!: RaceHistoryPlayerStatus;

  @ApiPropertyOptional({ nullable: true, minimum: 0 })
  @IsOptional()
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(0)
  finishTime?: number | null;

  @ApiPropertyOptional({ nullable: true, minimum: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  lapCount?: number | null;

  @ApiPropertyOptional({ nullable: true, minimum: 0 })
  @IsOptional()
  @IsInt()
  @Min(0)
  completedLaps?: number | null;

  @ApiPropertyOptional({ type: Number, isArray: true })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsNumber({}, { each: true })
  lapTimes?: number[];

  @ApiPropertyOptional({ nullable: true, minimum: 0 })
  @IsOptional()
  @IsInt()
  @Min(0)
  completedCheckpoints?: number | null;

  @ApiPropertyOptional({ nullable: true, minimum: 0 })
  @IsOptional()
  @IsInt()
  @Min(0)
  totalCheckpoints?: number | null;
}

export class CreateRaceHistoryDto {
  @ApiProperty({ example: '0123456789abcdef0123456789abcdef' })
  @IsString()
  @Matches(/^[0-9a-f]{32}$/)
  raceId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(80)
  @Matches(/^[a-zA-Z0-9_-]+$/)
  roomId!: string;

  @ApiProperty({ enum: RaceHistoryMode })
  @IsEnum(RaceHistoryMode)
  mode!: RaceHistoryMode;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  trackId!: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  trackSeed?: string | null;

  @ApiPropertyOptional({ nullable: true, minimum: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100000)
  generatorVersion?: number | null;

  @ApiProperty({ format: 'date-time' })
  @IsDateString()
  startedAt!: string;

  @ApiProperty({ format: 'date-time' })
  @IsDateString()
  endedAt!: string;

  @ApiProperty({ minimum: 0 })
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(0)
  @Max(86400000)
  durationMs!: number;

  @ApiProperty({ enum: RaceHistoryEndReason })
  @IsEnum(RaceHistoryEndReason)
  endReason!: RaceHistoryEndReason;

  @ApiProperty()
  @IsBoolean()
  isDraw!: boolean;

  @ApiPropertyOptional({ enum: RaceHistorySlot, nullable: true })
  @IsOptional()
  @IsEnum(RaceHistorySlot)
  winnerSlot?: RaceHistorySlot | null;

  @ApiProperty({ type: RaceHistoryPlayerInputDto, isArray: true })
  @IsArray()
  @ArrayMinSize(2)
  @ArrayMaxSize(2)
  @ValidateNested({ each: true })
  @Type(() => RaceHistoryPlayerInputDto)
  players!: RaceHistoryPlayerInputDto[];
}

export class RaceHistoryDto extends CreateRaceHistoryDto {
  @ApiProperty()
  id!: string;

  @ApiProperty()
  ownerUserId!: string;
}

export class CreateRaceHistoryResponseDto extends RaceHistoryDto {
  @ApiProperty({ description: 'True when this result was already stored.' })
  duplicate!: boolean;
}

export class RaceHistoryListDto {
  @ApiProperty({ type: RaceHistoryDto, isArray: true })
  items!: RaceHistoryDto[];

  @ApiPropertyOptional({ nullable: true })
  nextCursor!: string | null;
}

export class RaceHistoryQueryDto {
  @ApiPropertyOptional({ minimum: 1, maximum: 50, default: 20 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit = 20;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(256)
  cursor?: string;
}
