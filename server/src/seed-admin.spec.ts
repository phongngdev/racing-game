import { assertDevelopmentSeedAllowed } from './seed-admin.guard.js';

describe('assertDevelopmentSeedAllowed', () => {
  it('allows the explicit development environment', () => {
    expect(() => assertDevelopmentSeedAllowed('development')).not.toThrow();
  });

  it.each([undefined, 'test', 'production'])(
    'blocks Admin seeding when NODE_ENV is %s',
    (environment) => {
      expect(() => assertDevelopmentSeedAllowed(environment)).toThrow(
        'Admin seeding is allowed only when NODE_ENV=development.',
      );
    },
  );
});
