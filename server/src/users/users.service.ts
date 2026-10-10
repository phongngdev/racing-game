import { ConflictException, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import * as argon2 from 'argon2';
import { Model } from 'mongoose';
import { RegisterDto } from './user.dto.js';
import { PublicUser } from './public-user.dto.js';
import { User, UserDocument, UserRole } from './user.schema.js';

@Injectable()
export class UsersService {
  constructor(@InjectModel(User.name) private readonly users: Model<User>) {}

  createRegisteredUser(input: RegisterDto): Promise<PublicUser> {
    return this.createAccount(input, UserRole.User);
  }

  createAdmin(input: RegisterDto): Promise<PublicUser> {
    return this.createAccount(input, UserRole.Admin);
  }

  async verifyCredentials(
    username: string,
    password: string,
  ): Promise<PublicUser | null> {
    const user = await this.users
      .findOne({ username })
      .select('+passwordHash')
      .exec();
    if (!user || !(await argon2.verify(user.passwordHash, password))) {
      return null;
    }
    return this.toPublicUser(user);
  }

  async findPublicById(id: string): Promise<PublicUser | null> {
    const user = await this.users.findById(id).exec();
    return user ? this.toPublicUser(user) : null;
  }

  private async createAccount(
    input: RegisterDto,
    role: UserRole,
  ): Promise<PublicUser> {
    const passwordHash = await argon2.hash(input.password, {
      type: argon2.argon2id,
    });

    try {
      const user = await this.users.create({
        username: input.username,
        email: input.email,
        passwordHash,
        role,
      });
      return this.toPublicUser(user);
    } catch (error) {
      if (this.isDuplicateKeyError(error)) {
        throw new ConflictException('Username or email already exists.');
      }
      throw error;
    }
  }

  private toPublicUser(user: UserDocument): PublicUser {
    return {
      id: user._id.toString(),
      username: user.username,
      email: user.email,
      role: user.role,
    };
  }

  private isDuplicateKeyError(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 11000
    );
  }
}
