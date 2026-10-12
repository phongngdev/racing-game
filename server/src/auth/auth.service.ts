import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { LoginDto, RegisterDto } from '../users/user.dto.js';
import { PublicUser } from '../users/public-user.dto.js';
import { UsersService } from '../users/users.service.js';
import { GoogleIdentityService } from './google-identity.service.js';
import { PasswordResetService } from './password-reset.service.js';

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
    private readonly google: GoogleIdentityService,
    private readonly passwordReset: PasswordResetService,
  ) {}

  register(input: RegisterDto): Promise<PublicUser> {
    return this.users.createRegisteredUser(input);
  }

  async login(input: LoginDto): Promise<{
    accessToken: string;
    user: PublicUser;
  }> {
    const user = await this.users.verifyCredentials(
      input.username,
      input.password,
    );
    if (!user) {
      throw new UnauthorizedException('Invalid username or password.');
    }

    return this.createLoginResponse(user);
  }

  async googleLogin(idToken: string, linkPassword?: string) {
    const identity = await this.google.verify(idToken);
    const user = await this.users.authenticateGoogle(identity, linkPassword);
    return this.createLoginResponse(user);
  }

  requestPasswordReset(email: string, ip: string) {
    return this.passwordReset.requestCode(email, ip);
  }

  resetPassword(email: string, otp: string, newPassword: string, ip: string) {
    return this.passwordReset.resetPassword(email, otp, newPassword, ip);
  }

  async getCurrentUser(id: string): Promise<PublicUser> {
    const user = await this.users.findPublicById(id);
    if (!user) {
      throw new UnauthorizedException('Invalid or expired access token.');
    }
    return user;
  }

  async getCurrentSessionUser(
    id: string,
    authVersion: number,
  ): Promise<PublicUser> {
    const user = await this.users.findSessionUser(id, authVersion);
    if (!user) {
      throw new UnauthorizedException('Invalid or expired access token.');
    }
    return user;
  }

  private async createLoginResponse(user: PublicUser) {
    const version = await this.users.getAuthVersion(user.id);
    return {
      accessToken: await this.jwt.signAsync({
        sub: user.id,
        authVersion: version,
      }),
      user,
    };
  }
}
