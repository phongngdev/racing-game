import { ConflictException } from '@nestjs/common';
import * as argon2 from 'argon2';
import type { Model } from 'mongoose';
import { PublicUser } from './public-user.dto.js';
import { RegisterDto } from './user.dto.js';
import { User, UserRole } from './user.schema.js';
import { UsersService } from './users.service.js';

describe('UsersService', () => {
  const storedUser = {
    _id: { toString: () => '66c1a10d6b9a5e9a6a1c0123' },
    username: 'racer_01',
    email: 'racer@example.com',
    passwordHash: '',
    role: UserRole.User,
  };
  const users = { create: vi.fn(), findOne: vi.fn(), findById: vi.fn() };
  let service: UsersService;

  beforeEach(() => {
    vi.clearAllMocks();
    service = new UsersService(users as unknown as Model<User>);
  });

  it('stores an Argon2id hash and returns only public User fields', async () => {
    users.create.mockImplementation(async (input) => {
      Object.assign(storedUser, input);
      return storedUser;
    });
    const input: RegisterDto = {
      username: storedUser.username,
      email: storedUser.email,
      password: 'test-password-123',
    };

    const publicUser = await service.createRegisteredUser(input);

    expect(await argon2.verify(storedUser.passwordHash, input.password)).toBe(
      true,
    );
    expect(storedUser.passwordHash).not.toBe(input.password);
    expect(storedUser.role).toBe(UserRole.User);
    expect(publicUser).toEqual<PublicUser>({
      id: '66c1a10d6b9a5e9a6a1c0123',
      username: storedUser.username,
      email: storedUser.email,
      role: UserRole.User,
    });
    expect(publicUser).not.toHaveProperty('passwordHash');
  });

  it('maps Mongo duplicate key errors to 409', async () => {
    users.create.mockRejectedValue({ code: 11000 });

    await expect(
      service.createRegisteredUser({
        username: 'racer_01',
        email: 'racer@example.com',
        password: 'test-password-123',
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});
