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
  };
  const jwt = { signAsync: vi.fn() };
  let service: AuthService;

  beforeEach(() => {
    vi.clearAllMocks();
    service = new AuthService(users as unknown as UsersService, jwt as never);
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
    jwt.signAsync.mockResolvedValue('signed-access-token');

    await expect(
      service.login({ username: user.username, password: 'test-password-123' }),
    ).resolves.toEqual({ accessToken: 'signed-access-token', user });
    expect(jwt.signAsync).toHaveBeenCalledWith({ sub: user.id });
  });

  it('rejects bad credentials without issuing a token', async () => {
    users.verifyCredentials.mockResolvedValue(null);

    await expect(
      service.login({ username: user.username, password: 'wrong-pass-123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(jwt.signAsync).not.toHaveBeenCalled();
  });

  it('rejects a token subject after its account is gone', async () => {
    users.findPublicById.mockResolvedValue(null);

    await expect(service.getCurrentUser(user.id)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
