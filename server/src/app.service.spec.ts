import { ServiceUnavailableException } from '@nestjs/common';
import { AppService } from './app.service.js';

describe('AppService', () => {
  it('reports MongoDB as connected after a successful ping', async () => {
    const service = new AppService({
      db: { admin: () => ({ ping: vi.fn().mockResolvedValue({ ok: 1 }) }) },
    } as never);

    await expect(service.checkDatabase()).resolves.toEqual({
      status: 'ok',
      database: 'connected',
    });
  });

  it('reports MongoDB as unavailable when the ping fails', async () => {
    const service = new AppService({
      db: {
        admin: () => ({
          ping: vi.fn().mockRejectedValue(new Error('offline')),
        }),
      },
    } as never);

    await expect(service.checkDatabase()).rejects.toMatchObject({
      status: 503,
      response: { status: 'error', database: 'unavailable' },
    } satisfies Partial<ServiceUnavailableException>);
  });

  it('reports MongoDB as unavailable before a connection is ready', async () => {
    const service = new AppService({ db: undefined } as never);

    await expect(service.checkDatabase()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
