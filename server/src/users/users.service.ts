import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
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
    if (
      !user?.passwordHash ||
      !(await argon2.verify(user.passwordHash, password))
    ) {
      return null;
    }
    return this.toPublicUser(user);
  }

  async findPublicById(id: string): Promise<PublicUser | null> {
    const user = await this.users.findById(id).exec();
    return user ? this.toPublicUser(user) : null;
  }

  async findSessionUser(
    id: string,
    version: number,
  ): Promise<PublicUser | null> {
    const user = await this.users.findById(id).select('+authVersion').exec();
    if (!user || user.authVersion !== version) return null;
    return this.toPublicUser(user);
  }

  async getAuthVersion(id: string): Promise<number> {
    const user = await this.users.findById(id).select('+authVersion').exec();
    if (!user) throw new UnauthorizedException('Account no longer exists.');
    return user.authVersion;
  }

  async authenticateGoogle(
    identity: { sub: string; email: string },
    linkPassword?: string,
  ): Promise<PublicUser> {
    const linked = await this.users.findOne({ googleSub: identity.sub }).exec();
    if (linked) return this.toPublicUser(linked);

    const existing = await this.users.findOne({ email: identity.email }).exec();
    if (existing) {
      if (!linkPassword) {
        throw new ConflictException({
          code: 'GOOGLE_LINK_REQUIRED',
          message: 'Enter your account password to link Google.',
        });
      }
      const withPassword = await this.users
        .findById(existing._id)
        .select('+passwordHash')
        .exec();
      if (
        !withPassword?.passwordHash ||
        !(await argon2.verify(withPassword.passwordHash, linkPassword))
      ) {
        throw new UnauthorizedException('Invalid account password.');
      }
      const result = await this.users
        .findOneAndUpdate(
          {
            _id: withPassword._id,
            email: identity.email,
            googleSub: { $exists: false },
          },
          { $set: { googleSub: identity.sub } },
          { returnDocument: 'after' },
        )
        .exec();
      if (result) return this.toPublicUser(result);
      const raced = await this.users
        .findOne({ googleSub: identity.sub })
        .exec();
      if (raced) return this.toPublicUser(raced);
      throw new ConflictException('Google account is already linked.');
    }

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const user = await this.users.create({
          username: `google_${randomBytes(7).toString('hex')}`,
          email: identity.email,
          googleSub: identity.sub,
          role: UserRole.User,
        });
        return this.toPublicUser(user);
      } catch (error) {
        if (!this.isDuplicateKeyError(error)) throw error;
        const raced = await this.users
          .findOne({ googleSub: identity.sub })
          .exec();
        if (raced) return this.toPublicUser(raced);
        const emailOwner = await this.users
          .findOne({ email: identity.email })
          .exec();
        if (emailOwner) {
          throw new ConflictException({
            code: 'GOOGLE_LINK_REQUIRED',
            message: 'Enter your account password to link Google.',
          });
        }
      }
    }
    throw new ConflictException('Could not create Google account.');
  }

  async findByEmail(email: string): Promise<{ id: string } | null> {
    const user = await this.users.findOne({ email }).select('_id').exec();
    return user ? { id: user._id.toString() } : null;
  }

  async setResetOtp(id: string, hash: string, expiresAt: Date): Promise<void> {
    await this.users
      .updateOne(
        { _id: id },
        {
          $set: {
            resetOtpHash: hash,
            resetOtpExpiresAt: expiresAt,
            resetOtpAttempts: 0,
          },
        },
      )
      .exec();
  }

  async clearResetOtp(id: string, hash: string): Promise<void> {
    await this.users
      .updateOne(
        { _id: id, resetOtpHash: hash },
        {
          $unset: {
            resetOtpHash: 1,
            resetOtpExpiresAt: 1,
            resetOtpAttempts: 1,
          },
        },
      )
      .exec();
  }

  async consumeResetOtp(
    email: string,
    hash: string,
    passwordHash: string,
    now: Date,
  ): Promise<boolean> {
    const result = await this.users
      .updateOne(
        {
          email,
          resetOtpHash: hash,
          resetOtpExpiresAt: { $gt: now },
          resetOtpAttempts: { $lte: 5 },
        },
        {
          $set: { passwordHash },
          $inc: { authVersion: 1 },
          $unset: {
            resetOtpHash: 1,
            resetOtpExpiresAt: 1,
            resetOtpAttempts: 1,
          },
        },
      )
      .exec();
    return result.modifiedCount === 1;
  }

  async checkAndCountResetOtpAttempt(
    email: string,
    now: Date,
  ): Promise<{ hash: string; matched: boolean }> {
    const user = await this.users
      .findOneAndUpdate(
        {
          email,
          resetOtpHash: { $exists: true },
          resetOtpExpiresAt: { $gt: now },
          resetOtpAttempts: { $lt: 5 },
        },
        { $inc: { resetOtpAttempts: 1 } },
        { returnDocument: 'after' },
      )
      .select('+resetOtpHash +resetOtpExpiresAt +resetOtpAttempts')
      .exec();
    return {
      hash: user?.resetOtpHash ?? '',
      matched: Boolean(user),
    };
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
