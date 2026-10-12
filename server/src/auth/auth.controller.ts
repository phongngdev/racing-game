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
  ApiAcceptedResponse,
  ApiTooManyRequestsResponse,
  ApiServiceUnavailableResponse,
} from '@nestjs/swagger';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import { JwtAuthGuard } from './jwt-auth.guard.js';
import { LoginResponseDto } from './login-response.dto.js';
import { LoginDto, RegisterDto } from '../users/user.dto.js';
import { PublicUserDto } from '../users/public-user.dto.js';
import type { PublicUser } from '../users/public-user.dto.js';
import { GoogleLoginDto } from './google-login.dto.js';
import { ForgotPasswordDto, ResetPasswordDto } from './password-reset.dto.js';

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

  @Post('google')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Sign in with a Google ID token or link it to a local account.',
  })
  @ApiOkResponse({ type: LoginResponseDto })
  @ApiUnauthorizedResponse({
    description: 'Google token or link password is invalid.',
  })
  @ApiConflictResponse({
    description: 'Email exists; retry with its local password.',
  })
  @ApiServiceUnavailableResponse({
    description: 'Google Sign-In is not configured.',
  })
  googleLogin(@Body() input: GoogleLoginDto): Promise<LoginResponseDto> {
    return this.auth.googleLogin(input.idToken, input.linkPassword);
  }

  @Post('forgot-password')
  @HttpCode(HttpStatus.ACCEPTED)
  @ApiOperation({ summary: 'Send a generic password reset code by email.' })
  @ApiAcceptedResponse({ description: 'A generic reset response is returned.' })
  @ApiBadRequestResponse({ description: 'Email address is invalid.' })
  @ApiTooManyRequestsResponse({ description: 'Request rate limit exceeded.' })
  @ApiServiceUnavailableResponse({
    description: 'Password reset is not configured.',
  })
  forgotPassword(
    @Body() input: ForgotPasswordDto,
    @Req() request: Request,
  ): Promise<{ message: string }> {
    return this.auth.requestPasswordReset(input.email, request.ip ?? 'unknown');
  }

  @Post('reset-password')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Set a new local password using the emailed code.' })
  @ApiOkResponse({ description: 'Password was reset; sign in again.' })
  @ApiBadRequestResponse({ description: 'Reset code is invalid or expired.' })
  @ApiTooManyRequestsResponse({
    description: 'Verification rate limit exceeded.',
  })
  @ApiServiceUnavailableResponse({
    description: 'Password reset is not configured.',
  })
  resetPassword(
    @Body() input: ResetPasswordDto,
    @Req() request: Request,
  ): Promise<{ message: string }> {
    return this.auth.resetPassword(
      input.email,
      input.otp,
      input.newPassword,
      request.ip ?? 'unknown',
    );
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
