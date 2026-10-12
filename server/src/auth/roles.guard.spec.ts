import {
  ExecutionContext,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '../users/user.schema.js';
import { RolesGuard } from './roles.guard.js';

describe('RolesGuard', () => {
  const reflector = { getAllAndOverride: vi.fn() };
  const guard = new RolesGuard(reflector as unknown as Reflector);
  const handler = () => undefined;
  const controller = class {};

  beforeEach(() => vi.clearAllMocks());

  it('allows Admin on an Admin-only route', () => {
    reflector.getAllAndOverride.mockReturnValue([UserRole.Admin]);
    expect(guard.canActivate(context({ user: { role: UserRole.Admin } }))).toBe(
      true,
    );
  });

  it('rejects User on an Admin-only route', () => {
    reflector.getAllAndOverride.mockReturnValue([UserRole.Admin]);
    expect(() =>
      guard.canActivate(context({ user: { role: UserRole.User } })),
    ).toThrow(ForbiddenException);
  });

  it('requires authentication when a protected role is set', () => {
    reflector.getAllAndOverride.mockReturnValue([UserRole.Admin]);
    expect(() => guard.canActivate(context({}))).toThrow(UnauthorizedException);
  });

  it('allows authenticated roles when a route has no role restriction', () => {
    reflector.getAllAndOverride.mockReturnValue(undefined);
    expect(guard.canActivate(context({}))).toBe(true);
  });

  function context(request: object): ExecutionContext {
    return {
      getHandler: () => handler,
      getClass: () => controller,
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;
  }
});
