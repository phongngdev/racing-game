import { BadRequestException } from '@nestjs/common';
import { createHmac } from 'node:crypto';
import { PasswordResetService } from './password-reset.service.js';
import { UsersService } from '../users/users.service.js';
import { EmailService } from './email.service.js';
import { RateLimitService } from './rate-limit.service.js';

describe('PasswordResetService', () => {
  const pepper = 'test-only-otp-pepper-that-is-long-enough-123';
  const users = {
    findByEmail: vi.fn(),
    setResetOtp: vi.fn(),
    clearResetOtp: vi.fn(),
    checkAndCountResetOtpAttempt: vi.fn(),
    consumeResetOtp: vi.fn(),
  };
  const email = { sendPasswordResetCode: vi.fn() };
  const rates = { consume: vi.fn() };
  const config = {
    get: vi.fn((key: string) =>
      key === 'RESET_OTP_PEPPER' ? pepper : undefined,
    ),
  };
  let service: PasswordResetService;

  beforeEach(() => {
    vi.clearAllMocks();
    users.findByEmail.mockResolvedValue(null);
    users.setResetOtp.mockResolvedValue(undefined);
    users.clearResetOtp.mockResolvedValue(undefined);
    users.checkAndCountResetOtpAttempt.mockResolvedValue({
      hash: '',
      matched: false,
    });
    users.consumeResetOtp.mockResolvedValue(false);
    email.sendPasswordResetCode.mockResolvedValue(undefined);
    rates.consume.mockResolvedValue(undefined);
    service = new PasswordResetService(
      users as unknown as UsersService,
      email as unknown as EmailService,
      rates as unknown as RateLimitService,
      config as never,
    );
  });

  it('sends the same generic reset response and email for an unknown address', async () => {
    await expect(
      service.requestCode('unknown@example.com', '127.0.0.1'),
    ).resolves.toEqual({
      message: 'If the account exists, a reset code has been sent.',
    });
    expect(users.setResetOtp).not.toHaveBeenCalled();
    expect(email.sendPasswordResetCode).toHaveBeenCalledWith(
      'unknown@example.com',
      expect.stringMatching(/^\d{6}$/),
    );
    expect(rates.consume).toHaveBeenCalledTimes(2);
  });

  it('counts invalid OTP attempts and rejects without changing the password', async () => {
    users.checkAndCountResetOtpAttempt.mockResolvedValue({
      hash: '0'.repeat(64),
      matched: true,
    });

    await expect(
      service.resetPassword(
        'racer@example.com',
        '000000',
        'new-password-123',
        '127.0.0.1',
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(users.checkAndCountResetOtpAttempt).toHaveBeenCalledOnce();
    expect(users.consumeResetOtp).not.toHaveBeenCalled();
  });

  it('hashes OTPs with the server pepper and consumes a valid code once', async () => {
    const code = '481902';
    const emailAddress = 'racer@example.com';
    const hash = createHmac('sha256', pepper)
      .update(`${emailAddress}:${code}`)
      .digest('hex');
    users.checkAndCountResetOtpAttempt.mockResolvedValue({
      hash,
      matched: true,
    });
    users.consumeResetOtp.mockResolvedValue(true);

    await expect(
      service.resetPassword(
        emailAddress,
        code,
        'new-password-123',
        '127.0.0.1',
      ),
    ).resolves.toEqual({
      message: 'Password reset successfully. Please sign in again.',
    });
    expect(users.consumeResetOtp).toHaveBeenCalledWith(
      emailAddress,
      hash,
      expect.any(String),
      expect.any(Date),
    );
  });
});
