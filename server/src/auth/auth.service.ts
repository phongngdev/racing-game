import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { LoginDto, RegisterDto } from '../users/user.dto.js';
import { PublicUser } from '../users/public-user.dto.js';
import { UsersService } from '../users/users.service.js';

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
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

    return {
      accessToken: await this.jwt.signAsync({ sub: user.id }),
      user,
    };
  }

  async getCurrentUser(id: string): Promise<PublicUser> {
    const user = await this.users.findPublicById(id);
    if (!user) {
      throw new UnauthorizedException('Invalid or expired access token.');
    }
    return user;
  }
}
