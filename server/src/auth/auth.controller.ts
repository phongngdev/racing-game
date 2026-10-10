import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import { JwtAuthGuard } from './jwt-auth.guard.js';
import { LoginResponseDto } from './login-response.dto.js';
import { LoginDto, RegisterDto } from '../users/user.dto.js';
import { PublicUserDto } from '../users/public-user.dto.js';
import type { PublicUser } from '../users/public-user.dto.js';

type AuthenticatedRequest = Request & { user: PublicUser };

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  @ApiOperation({ summary: 'Create a public User account.' })
  @ApiCreatedResponse({ type: PublicUserDto })
  @ApiBadRequestResponse({ description: 'Registration data is invalid.' })
  @ApiConflictResponse({ description: 'Username or email already exists.' })
  register(@Body() input: RegisterDto): Promise<PublicUser> {
    return this.auth.register(input);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Sign in with username and password.' })
  @ApiOkResponse({ type: LoginResponseDto })
  @ApiBadRequestResponse({ description: 'Login data is invalid.' })
  @ApiUnauthorizedResponse({
    description: 'Username or password is incorrect.',
  })
  login(@Body() input: LoginDto): Promise<LoginResponseDto> {
    return this.auth.login(input);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Get the authenticated user and current role.' })
  @ApiOkResponse({ type: PublicUserDto })
  @ApiUnauthorizedResponse({
    description: 'Bearer token is missing or invalid.',
  })
  getMe(@Req() request: AuthenticatedRequest): PublicUser {
    return request.user;
  }
}
