import { UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import { PublicUser } from '../users/public-user.dto.js';
import { UserRole } from '../users/user.schema.js';
import { UsersService } from '../users/users.service.js';

describe('AuthService', () => {
  const user: PublicUser = {
    id: '66c1a10d6b9a5e9a6a1c0123',
    username: 'racer_01',
    email: 'racer@example.com',
    role: UserRole.User,
  };
  const users = {
    createRegisteredUser: vi.fn(),
    verifyCredentials: vi.fn(),
    findPublicById: vi.fn(),
    getAuthVersion: vi.fn(),
    authenticateGoogle: vi.fn(),
  };
  const jwt = { signAsync: vi.fn() };
  const google = { verify: vi.fn() };
  const passwordReset = { requestCode: vi.fn(), resetPassword: vi.fn() };
  let service: AuthService;

  beforeEach(() => {
    vi.clearAllMocks();
    service = new AuthService(
      users as unknown as UsersService,
      jwt as never,
      google as never,
      passwordReset as never,
    );
  });

  it('always delegates public registration to User account creation', async () => {
    users.createRegisteredUser.mockResolvedValue(user);

    await expect(
      service.register({
        username: user.username,
        email: user.email,
        password: 'test-password-123',
      }),
    ).resolves.toEqual(user);
    expect(users.createRegisteredUser).toHaveBeenCalledOnce();
  });

  it('issues a JWT with the authenticated user id as subject', async () => {
    users.verifyCredentials.mockResolvedValue(user);
    users.getAuthVersion.mockResolvedValue(0);
    jwt.signAsync.mockResolvedValue('signed-access-token');

    await expect(
      service.login({ username: user.username, password: 'test-password-123' }),
    ).resolves.toEqual({ accessToken: 'signed-access-token', user });
    expect(jwt.signAsync).toHaveBeenCalledWith({
      sub: user.id,
      authVersion: 0,
    });
  });

  it('rejects bad credentials without issuing a token', async () => {
    users.verifyCredentials.mockResolvedValue(null);

    await expect(
      service.login({ username: user.username, password: 'wrong-pass-123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(jwt.signAsync).not.toHaveBeenCalled();
  });

  it('verifies a Google ID token and returns the existing JWT session shape', async () => {
    const identity = { sub: 'google-user-id', email: user.email };
    google.verify.mockResolvedValue(identity);
    users.authenticateGoogle.mockResolvedValue(user);
    users.getAuthVersion.mockResolvedValue(2);
    jwt.signAsync.mockResolvedValue('google-access-token');

    await expect(service.googleLogin('google-id-token')).resolves.toEqual({
      accessToken: 'google-access-token',
      user,
    });
    expect(google.verify).toHaveBeenCalledWith('google-id-token');
    expect(users.authenticateGoogle).toHaveBeenCalledWith(identity, undefined);
    expect(jwt.signAsync).toHaveBeenCalledWith({
      sub: user.id,
      authVersion: 2,
    });
  });

  it('rejects a token subject after its account is gone', async () => {
    users.findPublicById.mockResolvedValue(null);

    await expect(service.getCurrentUser(user.id)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
