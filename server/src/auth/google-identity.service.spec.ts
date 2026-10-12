import { UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { GoogleIdentityService } from './google-identity.service.js';

describe('GoogleIdentityService', () => {
  const webClientId = 'web.apps.googleusercontent.com';
  let service: GoogleIdentityService;
  let verifyIdToken: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.restoreAllMocks();
    service = new GoogleIdentityService({
      get: () => webClientId,
    } as unknown as ConfigService);
    verifyIdToken = vi.spyOn(OAuth2Client.prototype, 'verifyIdToken');
  });

  it('verifies the token against the configured server audience', async () => {
    verifyIdToken.mockResolvedValue({
      getPayload: () => ({
        sub: 'google-subject',
        email: 'Racer@Example.com',
        email_verified: true,
      }),
    } as never);

    await expect(service.verify('google-id-token')).resolves.toEqual({
      sub: 'google-subject',
      email: 'racer@example.com',
    });
    expect(verifyIdToken).toHaveBeenCalledWith({
      idToken: 'google-id-token',
      audience: webClientId,
    });
  });

  it('rejects unverified email claims', async () => {
    verifyIdToken.mockResolvedValue({
      getPayload: () => ({
        sub: 'google-subject',
        email: 'racer@example.com',
        email_verified: false,
      }),
    } as never);

    await expect(service.verify('google-id-token')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
