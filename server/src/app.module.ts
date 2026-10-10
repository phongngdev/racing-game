import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';

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

        return { ...environment, PORT: port };
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
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
