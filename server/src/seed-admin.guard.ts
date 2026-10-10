export function assertDevelopmentSeedAllowed(
  environment: string | undefined,
): void {
  if (environment !== 'development') {
    throw new Error('Admin seeding is allowed only when NODE_ENV=development.');
  }
}
