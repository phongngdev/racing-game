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

  it('routes current-generation haptics and clamps collision intensity', () => {
    const gateway = new ControllerGateway();
    const phone = socket();
    const game = socket();
    gateway.onRegister(phone, { role: 'phone', version: 1 });
    const generation = messages(phone)[0]?.data.generation as number;
    gateway.onRegister(game, { role: 'game', version: 1 });

    gateway.onCollision(game, { generation, intensity: 1.4 });
    expect(messages(phone).at(-1)).toEqual({
      event: 'collision',
      data: { generation, intensity: 1 },
    });
    const afterCollision = phone.sent.length;
    gateway.onHaptic(game, { generation: generation + 1, event: 'go' });
    gateway.onHaptic(phone, { generation, event: 'go' });
    expect(phone.sent).toHaveLength(afterCollision);
    gateway.onHaptic(game, { generation, event: 'go' });
    expect(messages(phone).at(-1)).toEqual({
      event: 'haptic',
      data: { generation, event: 'go' },
    });
    gateway.onHaptic(game, { generation, event: 'impact' });
    expect(phone.sent).toHaveLength(afterCollision + 1);
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
    gateway.onHaptic(game, {
      generation: phoneRegistration?.data.generation,
      event: 'finish',
    });
    expect(messages(phone).at(-1)).toEqual({
      event: 'haptic',
      data: { generation: phoneRegistration?.data.generation, event: 'finish' },
    });
  });

  it('routes v3 input only from the phone socket currently owning its room slot', () => {
    const gateway = new ControllerGateway();
    const game = socket();
    const phone = socket();
    const otherPhone = socket();
    gateway.onRegister(game, {
      role: 'game',
      version: 3,
      action: 'create',
    });
    const registration = messages(game)[0]?.data;
    expect(messages(game)[0]?.event).toBe('registered');
    expect(registration?.invites[0]?.slotId).toBe('p1');

    gateway.onRegister(phone, {
      role: 'phone',
      version: 3,
      action: 'join',
      roomId: registration?.roomId,
      slotId: 'p1',
      pairingToken: registration?.invites[0]?.pairingToken,
    });
    const phoneRegistration = messages(phone)[0]?.data;
    expect(phoneRegistration).toMatchObject({ slotId: 'p1', player: 'red' });

    gateway.onRegister(otherPhone, {
      role: 'phone',
      version: 3,
      action: 'join',
      roomId: registration?.roomId,
      slotId: 'p1',
      pairingToken: registration?.invites[0]?.pairingToken,
    });
    expect(messages(otherPhone)[0]?.data.code).toBe('slot_in_use');

    const input = {
      roomId: registration?.roomId,
      slotId: 'p1',
      generation: phoneRegistration?.generation,
      seq: 0,
      steering: 0.5,
      throttle: 1,
      reverse: 0,
      brake: 0,
    };
    gateway.onInput(phone, input);
    expect(messages(game).at(-1)).toEqual({ event: 'input', data: input });

    const count = game.sent.length;
    gateway.onInput(phone, { ...input, roomId: 'another-room', seq: 1 });
    gateway.onInput(phone, { ...input, slotId: 'p2', seq: 1 });
    gateway.onInput(otherPhone, { ...input, seq: 1 });
    expect(game.sent).toHaveLength(count);

    gateway.onHaptic(game, {
      roomId: registration?.roomId,
      slotId: 'p1',
      generation: phoneRegistration?.generation,
      event: 'go',
    });
    expect(messages(phone).at(-1)).toEqual({
      event: 'haptic',
      data: {
        roomId: registration?.roomId,
        slotId: 'p1',
        generation: phoneRegistration?.generation,
        event: 'go',
      },
    });
    const hapticCount = phone.sent.length;
    gateway.onHaptic(game, {
      roomId: registration?.roomId,
      slotId: 'p2',
      generation: phoneRegistration?.generation,
      event: 'go',
    });
    expect(phone.sent).toHaveLength(hapticCount);

    gateway.onSlotLeave(phone, {
      roomId: registration?.roomId,
      slotId: 'p1',
      generation: phoneRegistration?.generation,
    });
    expect(messages(phone).at(-1)?.event).toBe('slot_left');
    expect(messages(game).at(-1)?.event).toBe('room_state');
    gateway.onModuleDestroy();
  });

  it('keeps separate room and slot state and requires host ownership for reconfiguration', () => {
    const gateway = new ControllerGateway();
    const firstGame = socket();
    const secondGame = socket();
    gateway.onRegister(firstGame, { role: 'game', version: 3, action: 'create' });
    gateway.onRegister(secondGame, { role: 'game', version: 3, action: 'create' });
    const firstRoomId = messages(firstGame)[0]?.data.roomId as string;
    const firstRequest = 'configure-p2';

    gateway.onSlotConfig(secondGame, {
      roomId: firstRoomId,
      slotId: 'p2',
      source: 'phone',
      requestId: firstRequest,
    });
    expect(messages(secondGame).at(-1)?.event).toBe('error');

    gateway.onSlotConfig(firstGame, {
      roomId: firstRoomId,
      slotId: 'p2',
      source: 'phone',
      requestId: firstRequest,
    });
    expect(messages(firstGame).some((message) => message.event === 'slot_invite')).toBe(true);
    expect(messages(firstGame).some((message) =>
      message.event === 'slot_configured' && message.data.requestId === firstRequest,
    )).toBe(true);

    const invite = messages(firstGame).find(
      (message) =>
        message.event === 'slot_invite' && message.data.slotId === 'p2',
    )?.data;
    const p2 = socket();
    gateway.onRegister(p2, {
      role: 'phone',
      version: 3,
      action: 'join',
      roomId: firstRoomId,
      slotId: 'p2',
      pairingToken: invite?.pairingToken,
    });
    expect(messages(p2)[0]?.data).toMatchObject({
      roomId: firstRoomId,
      slotId: 'p2',
      player: 'blue',
    });
    gateway.onModuleDestroy();
  });
});
