import { PairingSessionService } from './pairing-session.service.js';

describe('PairingSessionService', () => {
  it('consumes the QR token once and rotates a short lived resume token', () => {
    const service = new PairingSessionService();
    const session = service.create(1000);
    const joined = service.join(session.id, session.pairingToken, 1100);
    expect(joined.ok).toBe(true);
    if (!joined.ok) throw new Error('Expected pairing to succeed.');
    expect(joined.session.generation).toBe(1);
    expect(service.join(session.id, session.pairingToken, 1200)).toEqual({
      ok: false,
      code: 'phone_already_joined',
    });

    service.phoneDisconnected(session, 2000);
    expect(service.join(session.id, session.pairingToken, 2001)).toEqual({
      ok: false,
      code: 'phone_already_joined',
    });
    const resumed = service.resume(session.id, joined.credential, 2500);
    expect(resumed.ok).toBe(true);
    if (!resumed.ok) throw new Error('Expected resume to succeed.');
    expect(resumed.session.generation).toBe(2);
    expect(resumed.credential).not.toBe(joined.credential);
    expect(service.resume(session.id, joined.credential, 2600)).toEqual({
      ok: false,
      code: 'resume_expired',
    });
  });

  it('rejects a bad token and expires an unclaimed pairing', () => {
    const service = new PairingSessionService();
    const session = service.create(1000);
    expect(service.join(session.id, 'wrong-token', 1100)).toEqual({
      ok: false,
      code: 'invalid_pairing',
    });
    expect(service.expired(session, 1000 + 5 * 60 * 1000)).toBe(true);
    expect(
      service.join(session.id, session.pairingToken, 1000 + 5 * 60 * 1000),
    ).toEqual({ ok: false, code: 'pairing_expired' });
  });
});
