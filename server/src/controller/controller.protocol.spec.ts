import {
  allowedControllerOrigins,
  isControllerInput,
  isRole,
} from './controller.protocol.js';

describe('controller protocol validation', () => {
  it('accepts normalized finite input and rejects invalid ranges', () => {
    expect(
      isControllerInput({
        seq: 0,
        steering: -1,
        throttle: 1,
        brake: 0,
      }),
    ).toBe(true);
    expect(
      isControllerInput({
        seq: 1,
        steering: 1.01,
        throttle: 0,
        brake: 0,
      }),
    ).toBe(false);
    expect(
      isControllerInput({
        seq: 1,
        steering: 0,
        throttle: Number.NaN,
        brake: 0,
      }),
    ).toBe(false);
    expect(
      isControllerInput({
        seq: Number.MAX_SAFE_INTEGER + 1,
        steering: 0,
        throttle: 0,
        brake: 0,
      }),
    ).toBe(false);
  });

  it('allows only declared roles and exact browser origins', () => {
    expect(isRole('game')).toBe(true);
    expect(isRole('phone')).toBe(true);
    expect(isRole('spectator')).toBe(false);
    const previous = process.env['CONTROLLER_ALLOWED_ORIGINS'];
    process.env['CONTROLLER_ALLOWED_ORIGINS'] = 'http://192.168.1.8:5174';
    expect(allowedControllerOrigins().has('http://192.168.1.8:5174')).toBe(
      true,
    );
    expect(allowedControllerOrigins().has('http://192.168.1.8:5175')).toBe(
      false,
    );
    if (previous === undefined)
      delete process.env['CONTROLLER_ALLOWED_ORIGINS'];
    else process.env['CONTROLLER_ALLOWED_ORIGINS'] = previous;
  });
});
