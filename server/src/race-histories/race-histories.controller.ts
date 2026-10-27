import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CreateRaceHistoryResponseDto } from './race-history.dto.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { PublicUser } from '../users/public-user.dto.js';
import {
  CreateRaceHistoryDto,
  RaceHistoryDto,
  RaceHistoryListDto,
  RaceHistoryQueryDto,
} from './race-history.dto.js';
import { RaceHistoriesService } from './race-histories.service.js';

type AuthenticatedRequest = Request & { user: PublicUser };

@ApiTags('race-histories')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Bearer token is missing or invalid.' })
@UseGuards(JwtAuthGuard)
@Controller('race-histories')
export class RaceHistoriesController {
  constructor(private readonly histories: RaceHistoriesService) {}

  @Post()
  @ApiCreatedResponse({ type: CreateRaceHistoryResponseDto })
  async create(
    @Req() request: AuthenticatedRequest,
    @Body() input: CreateRaceHistoryDto,
  ): Promise<CreateRaceHistoryResponseDto> {
    const result = await this.histories.create(request.user, input);
    return Object.assign(new CreateRaceHistoryResponseDto(), result.history, {
      duplicate: result.duplicate,
    });
  }

  @Get('me')
  @ApiOkResponse({ type: RaceHistoryListDto })
  list(
    @Req() request: AuthenticatedRequest,
    @Query() query: RaceHistoryQueryDto,
  ): Promise<RaceHistoryListDto> {
    return this.histories.list(request.user, query.limit, query.cursor);
  }

  @Get(':id')
  @ApiOkResponse({ type: RaceHistoryDto })
  @ApiNotFoundResponse({ description: 'History was not found for this user.' })
  findOne(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<RaceHistoryDto> {
    return this.histories.findOne(request.user, id);
  }
}
