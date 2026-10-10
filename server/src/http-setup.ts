import { ValidationPipe } from '@nestjs/common';
import type { INestApplication } from '@nestjs/common';
import { setupSwagger } from './swagger.js';

export function setupHttp(app: INestApplication): void {
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );
  setupSwagger(app);
}
