import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as argon2 from 'argon2';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { UsersService } from '../users/users.service.js';
import { EmailService } from './email.service.js';
import { RateLimitService } from './rate-limit.service.js';

const OTP_LIFETIME_MS = 5 * 60_000;
const RATE_WINDOW_MS = 15 * 60_000;
const GENERIC_RESPONSE = {
  message: 'If the account exists, a reset code has been sent.',
};

@Injectable()
export class PasswordResetService {
  constructor(
    private readonly users: UsersService,
    private readonly email: EmailService,
    private readonly rates: RateLimitService,
    private readonly config: ConfigService,
  ) {}

  async requestCode(
    email: string,
    ip: string,
  ): Promise<typeof GENERIC_RESPONSE> {
    const normalizedEmail = email.trim().toLowerCase();
    const pepper = this.getPepper();
    const now = new Date();
    const emailKey = this.rateKey(pepper, 'email', normalizedEmail);
    const ipKey = this.rateKey(pepper, 'request-ip', ip);
    await this.rates.consume(`${emailKey}:send`, 3, RATE_WINDOW_MS, now);
    await this.rates.consume(ipKey, 10, RATE_WINDOW_MS, now);

    const otp = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const hash = this.otpHash(pepper, normalizedEmail, otp);
    const user = await this.users.findByEmail(normalizedEmail);
    if (user) {
      await this.users.setResetOtp(
        user.id,
        hash,
        new Date(now.getTime() + OTP_LIFETIME_MS),
      );
    }

    try {
      // Send the same generic message for unknown email addresses so SMTP work
      // and the response shape do not disclose whether a user exists.
      await this.email.sendPasswordResetCode(normalizedEmail, otp);
    } catch {
      if (user) await this.users.clearResetOtp(user.id, hash);
    }
    return GENERIC_RESPONSE;
  }

  async resetPassword(
    email: string,
    otp: string,
    newPassword: string,
    ip: string,
  ): Promise<{ message: string }> {
    const normalizedEmail = email.trim().toLowerCase();
    const pepper = this.getPepper();
    await this.rates.consume(
      this.rateKey(pepper, 'verify-ip', ip),
      30,
      RATE_WINDOW_MS,
    );

    const candidate = this.otpHash(pepper, normalizedEmail, otp);
    const attempt = await this.users.checkAndCountResetOtpAttempt(
      normalizedEmail,
      new Date(),
    );
    const stored = Buffer.from(attempt.hash, 'hex');
    const supplied = Buffer.from(candidate, 'hex');
    const valid =
      attempt.matched &&
      stored.length === supplied.length &&
      timingSafeEqual(stored, supplied);
    if (!valid) {
      throw new BadRequestException('Invalid or expired reset code.');
    }

    const passwordHash = await argon2.hash(newPassword, {
      type: argon2.argon2id,
    });
    const consumed = await this.users.consumeResetOtp(
      normalizedEmail,
      attempt.hash,
      passwordHash,
      new Date(),
    );
    if (!consumed) {
      throw new BadRequestException('Invalid or expired reset code.');
    }

    return { message: 'Password reset successfully. Please sign in again.' };
  }

  private getPepper(): string {
    const pepper = this.config.get<string>('RESET_OTP_PEPPER');
    if (!pepper || pepper.trim().length < 32) {
      throw new ServiceUnavailableException(
        'Password reset is not configured.',
      );
    }
    return pepper;
  }

  private otpHash(pepper: string, email: string, otp: string): string {
    return createHmac('sha256', pepper).update(`${email}:${otp}`).digest('hex');
  }

  private rateKey(pepper: string, purpose: string, value: string): string {
    const digest = createHmac('sha256', pepper)
      .update(`${purpose}:${value}`)
      .digest('hex');
    return `reset:${purpose}:${digest}`;
  }
}
