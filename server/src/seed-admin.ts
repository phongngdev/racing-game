import { NestFactory } from '@nestjs/core';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { AppModule } from './app.module.js';
import { assertDevelopmentSeedAllowed } from './seed-admin.guard.js';
import { RegisterDto } from './users/user.dto.js';
import { UsersService } from './users/users.service.js';

async function seedAdmin(): Promise<void> {
  assertDevelopmentSeedAllowed(process.env['NODE_ENV']);

  const input = plainToInstance(RegisterDto, {
    username: process.env['ADMIN_USERNAME'],
    email: process.env['ADMIN_EMAIL'],
    password: process.env['ADMIN_PASSWORD'],
  });
  const errors = await validate(input, {
    whitelist: true,
    forbidNonWhitelisted: true,
  });
  if (errors.length > 0) {
    throw new Error(
      'Set valid ADMIN_USERNAME, ADMIN_EMAIL, and ADMIN_PASSWORD environment values.',
    );
  }

  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn'],
  });
  try {
    await app.get(UsersService).createAdmin(input);
    console.log('Admin account created.');
  } finally {
    await app.close();
  }
}

seedAdmin().catch((error: unknown) => {
  console.error(
    error instanceof Error ? error.message : 'Admin seeding failed.',
  );
  process.exitCode = 1;
});
