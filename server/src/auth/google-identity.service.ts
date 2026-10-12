import {
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';

export interface GoogleIdentity {
  sub: string;
  email: string;
}

@Injectable()
export class GoogleIdentityService {
  private readonly client = new OAuth2Client();

  constructor(private readonly config: ConfigService) {}

  async verify(idToken: string): Promise<GoogleIdentity> {
    const audience = this.config.get<string>('GOOGLE_WEB_CLIENT_ID');
    if (!audience) {
      throw new ServiceUnavailableException(
        'Google Sign-In is not configured.',
      );
    }

    try {
      const ticket = await this.client.verifyIdToken({ idToken, audience });
      const payload = ticket.getPayload();
      if (
        !payload ||
        !payload.sub ||
        !payload.email ||
        payload.email_verified !== true
      ) {
        throw new Error('Required Google identity claims are missing.');
      }
      return { sub: payload.sub, email: payload.email.toLowerCase() };
    } catch {
      throw new UnauthorizedException('Invalid Google ID token.');
    }
  }
}
