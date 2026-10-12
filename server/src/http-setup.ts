import { ValidationPipe } from '@nestjs/common';
import type { INestApplication } from '@nestjs/common';
import { setupSwagger } from './swagger.js';

export function setupHttp(app: INestApplication): void {
  const allowedOrigins = (
    process.env['CORS_ORIGINS'] ??
    'http://localhost:5173,http://127.0.0.1:5173'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.enableCors({
    origin: allowedOrigins,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    credentials: false,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );
  setupSwagger(app);
}
