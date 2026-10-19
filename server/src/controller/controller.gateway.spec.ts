import type { WebSocket } from 'ws';
import { ControllerGateway } from './controller.gateway.js';

type StubSocket = WebSocket & {
  sent: string[];
  closeCode?: number;
};

function socket(): StubSocket {
  const stub = {
    OPEN: 1,
    readyState: 1,
    sent: [] as string[],
    send(data: string) {
      this.sent.push(data);
    },
    close(code: number) {
      this.closeCode = code;
      this.readyState = 2;
    },
  };
  return stub as unknown as StubSocket;
}

function messages(client: StubSocket): Array<{ event: string; data: any }> {
  return client.sent.map(
    (entry) => JSON.parse(entry) as { event: string; data: any },
  );
}

describe('ControllerGateway', () => {
  it('registers one phone and one game and relays only current ordered input', () => {
    const gateway = new ControllerGateway();
    const phone = socket();
    const game = socket();
    gateway.onRegister(phone, { role: 'phone', version: 1 });
    const generation = messages(phone)[0]?.data.generation as number;
    expect(messages(phone)[0]?.event).toBe('registered');

    gateway.onRegister(game, { role: 'game', version: 1 });
    expect(messages(game).map(({ event }) => event)).toEqual([
      'registered',
      'status',
    ]);
    expect(messages(game)[1]?.data).toMatchObject({
      phoneConnected: true,
      generation,
    });

    gateway.onInput(phone, {
      seq: 0,
      steering: -0.25,
      throttle: 1,
      reverse: 0,
      brake: 0,
    });
    expect(messages(game).at(-1)).toEqual({
      event: 'input',
      data: {
        seq: 0,
        steering: -0.25,
        throttle: 1,
        reverse: 0,
        brake: 0,
        generation,
      },
    });

    const count = game.sent.length;
    gateway.onInput(phone, {
      seq: 0,
      steering: 0,
      throttle: 0,
      reverse: 0,
      brake: 0,
    });
    gateway.onInput(phone, {
      seq: 1,
      steering: 2,
      throttle: 0,
      reverse: 0,
      brake: 0,
    });
    gateway.onInput(game, {
      seq: 1,
      steering: 0,
      throttle: 1,
      reverse: 0,
      brake: 0,
    });
    expect(game.sent).toHaveLength(count);

    gateway.onCollision(game, { generation: generation + 1 });
    gateway.onCollision(phone, { generation });
    expect(messages(phone)).toHaveLength(1);
    gateway.onCollision(game, { generation });
    expect(messages(phone).at(-1)).toEqual({
      event: 'collision',
      data: { generation },
    });
    gateway.onCollision(game, { generation });
    expect(messages(phone)).toHaveLength(2);

    gateway.handleDisconnect(phone);
    expect(messages(game).at(-1)).toEqual({
      event: 'status',
      data: { phoneConnected: false },
    });
  });

  it('rejects a second client taking the same role', () => {
    const gateway = new ControllerGateway();
    const first = socket();
    const second = socket();
    gateway.onRegister(first, { role: 'game', version: 1 });
    gateway.onRegister(second, { role: 'game', version: 1 });
    expect(messages(second)[0]).toEqual({
      event: 'error',
      data: { code: 'role_in_use' },
    });
    expect(second.closeCode).toBe(1008);
  });

  it('creates an isolated v2 session and accepts only its paired phone', () => {
    const gateway = new ControllerGateway();
    const game = socket();
    const phone = socket();
    const otherPhone = socket();
    gateway.onRegister(game, {
      role: 'game',
      version: 2,
      action: 'create',
    });
    const pairing = messages(game)[0]?.data;
    expect(messages(game)[0]?.event).toBe('registered');
    expect(pairing).toMatchObject({ role: 'game' });

    gateway.onRegister(phone, {
      role: 'phone',
      version: 2,
      action: 'join',
      sessionId: pairing?.sessionId,
      pairingToken: pairing?.pairingToken,
    });
    const phoneRegistration = messages(phone)[0];
    expect(phoneRegistration?.event).toBe('registered');
    expect(phoneRegistration?.data).toMatchObject({
      role: 'phone',
      sessionId: pairing?.sessionId,
      generation: 1,
    });
    expect(typeof phoneRegistration?.data.resumeToken).toBe('string');

    gateway.onRegister(otherPhone, {
      role: 'phone',
      version: 2,
      action: 'join',
      sessionId: pairing?.sessionId,
      pairingToken: pairing?.pairingToken,
    });
    expect(messages(otherPhone)[0]).toEqual({
      event: 'error',
      data: { code: 'phone_already_joined' },
    });
    expect(otherPhone.closeCode).toBe(1008);

    gateway.onInput(phone, {
      seq: 0,
      steering: 0.25,
      throttle: 0,
      reverse: 0,
      brake: 0,
    });
    expect(messages(game).at(-1)).toEqual({
      event: 'input',
      data: {
        seq: 0,
        steering: 0.25,
        throttle: 0,
        reverse: 0,
        brake: 0,
        generation: 1,
      },
    });
  });
});
