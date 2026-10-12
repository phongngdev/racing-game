import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule, JwtModuleOptions } from '@nestjs/jwt';
import { MongooseModule } from '@nestjs/mongoose';
import { UsersModule } from '../users/users.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { JwtAuthGuard } from './jwt-auth.guard.js';
import { RolesGuard } from './roles.guard.js';
import { GoogleIdentityService } from './google-identity.service.js';
import { PasswordResetService } from './password-reset.service.js';
import { EmailService } from './email.service.js';
import { RateLimitBucket, RateLimitBucketSchema } from './rate-limit.schema.js';
import { RateLimitService } from './rate-limit.service.js';

@Module({
  imports: [
    UsersModule,
    MongooseModule.forFeature([
      { name: RateLimitBucket.name, schema: RateLimitBucketSchema },
    ]),
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService): JwtModuleOptions => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: {
          algorithm: 'HS256',
          expiresIn:
            config.getOrThrow<
              NonNullable<JwtModuleOptions['signOptions']>['expiresIn']
            >('JWT_EXPIRES_IN'),
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtAuthGuard,
    RolesGuard,
    GoogleIdentityService,
    PasswordResetService,
    EmailService,
    RateLimitService,
  ],
  exports: [AuthService, JwtAuthGuard, RolesGuard, JwtModule],
})
export class AuthModule {}
