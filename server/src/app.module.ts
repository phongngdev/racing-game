import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { AuthModule } from './auth/auth.module.js';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { CategoriesModule } from './categories/categories.module.js';
import { ProductsModule } from './products/products.module.js';
import { UsersModule } from './users/users.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: (environment: Record<string, unknown>) => {
        const uri = environment['MONGODB_URI'];
        if (typeof uri !== 'string' || uri.trim() === '') {
          throw new Error('MONGODB_URI must be set.');
        }

        const port = Number(environment['PORT'] ?? 3000);
        if (!Number.isInteger(port) || port < 1 || port > 65535) {
          throw new Error('PORT must be an integer between 1 and 65535.');
        }

        const jwtSecret = environment['JWT_SECRET'];
        if (typeof jwtSecret !== 'string' || jwtSecret.trim().length < 32) {
          throw new Error('JWT_SECRET must contain at least 32 characters.');
        }

        const jwtExpiresIn = environment['JWT_EXPIRES_IN'] ?? '1h';
        if (
          typeof jwtExpiresIn !== 'string' ||
          !/^[1-9]\d*(s|m|h|d)$/.test(jwtExpiresIn)
        ) {
          throw new Error(
            'JWT_EXPIRES_IN must be a positive duration such as 1h.',
          );
        }

        return {
          ...environment,
          PORT: port,
          JWT_EXPIRES_IN: jwtExpiresIn,
        };
      },
    }),
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        uri: config.getOrThrow<string>('MONGODB_URI'),
        serverSelectionTimeoutMS: 5000,
        retryAttempts: 3,
        retryDelay: 1000,
      }),
    }),
    UsersModule,
    AuthModule,
    CategoriesModule,
    ProductsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
