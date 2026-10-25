import { Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { WsAdapter } from '@nestjs/platform-ws';
import WebSocket from 'ws';
import { ControllerModule } from './controller.module.js';

@Module({ imports: [ControllerModule] })
class RelayTestModule {}

interface RelayMessage {
  event: string;
  data: Record<string, unknown>;
}

let app: Awaited<ReturnType<typeof NestFactory.create>>;
let address: string;

function nextMessage(socket: WebSocket, event: string): Promise<RelayMessage> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.off('message', onMessage);
      reject(new Error(`Timed out waiting for ${event}`));
    }, 3000);
    const onMessage = async (raw: WebSocket.RawData) => {
      const text =
        raw instanceof Buffer
          ? raw.toString('utf8')
          : raw instanceof ArrayBuffer
            ? Buffer.from(raw).toString('utf8')
            : Array.isArray(raw)
              ? Buffer.concat(raw).toString('utf8')
              : await raw.text();
      const message = JSON.parse(text) as RelayMessage;
      if (message.event !== event) return;
      clearTimeout(timeout);
      socket.off('message', onMessage);
      resolve(message);
    };
    socket.on('message', onMessage);
  });
}

async function openSocket(url: string, options?: WebSocket.ClientOptions) {
  const socket = new WebSocket(url, options);
  await new Promise<void>((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  return socket;
}

beforeAll(async () => {
  app = await NestFactory.create(RelayTestModule, { logger: false });
  app.useWebSocketAdapter(new WsAdapter(app));
  await app.listen(0, '127.0.0.1');
  const serverAddress = app.getHttpServer().address();
  if (!serverAddress || typeof serverAddress === 'string') {
    throw new Error('Relay test server did not bind to a TCP port.');
  }
  address = `ws://127.0.0.1:${serverAddress.port}/controller`;
});

afterAll(async () => {
  await app.close();
});

describe('controller WebSocket relay integration', () => {
  it('relays phone input and signals disconnect without a database module', async () => {
    const game = await openSocket(address, {
      origin: 'http://localhost:5174',
    });
    const gameRegistered = nextMessage(game, 'registered');
    const gameStatus = nextMessage(game, 'status');
    game.send(
      JSON.stringify({ event: 'register', data: { role: 'game', version: 1 } }),
    );
    await gameRegistered;
    expect((await gameStatus).data['phoneConnected']).toBe(false);

    const phone = await openSocket(address);
    const phoneRegistered = nextMessage(phone, 'registered');
    const phonePresence = nextMessage(game, 'status');
    phone.send(
      JSON.stringify({
        event: 'register',
        data: { role: 'phone', version: 1 },
      }),
    );
    const registration = await phoneRegistered;
    expect(registration.data['role']).toBe('phone');
    expect((await phonePresence).data['phoneConnected']).toBe(true);

    const relayedInput = nextMessage(game, 'input');
    phone.send(
      JSON.stringify({
        event: 'input',
        data: {
          seq: 0,
          steering: -0.4,
          throttle: 1,
          reverse: 0,
          brake: 0,
        },
      }),
    );
    const input = await relayedInput;
    expect(input.data).toMatchObject({ seq: 0, steering: -0.4, throttle: 1 });
    expect(input.data['generation']).toBe(registration.data['generation']);

    const collision = nextMessage(phone, 'collision');
    game.send(
      JSON.stringify({
        event: 'collision',
        data: { generation: registration.data['generation'] },
      }),
    );
    expect((await collision).data['generation']).toBe(
      registration.data['generation'],
    );

    const disconnected = nextMessage(game, 'status');
    phone.close();
    expect((await disconnected).data['phoneConnected']).toBe(false);
    game.close();
  });

  it('rejects an unconfigured browser origin during the WebSocket handshake', async () => {
    const denied = new WebSocket(address, {
      origin: 'http://untrusted.invalid',
    });
    const outcome = await new Promise<'open' | 'rejected'>((resolve) => {
      denied.once('open', () => resolve('open'));
      denied.once('unexpected-response', () => resolve('rejected'));
      denied.once('error', () => resolve('rejected'));
    });
    expect(outcome).toBe('rejected');
  });

  it('pairs a phone to one v2 Practice session and resumes with its private token', async () => {
    const game = await openSocket(address, {
      origin: 'http://localhost:5173',
    });
    const gameRegistered = nextMessage(game, 'registered');
    const initialStatus = nextMessage(game, 'status');
    game.send(
      JSON.stringify({
        event: 'register',
        data: { role: 'game', version: 2, action: 'create' },
      }),
    );
    const pairing = await gameRegistered;
    await initialStatus;
    expect(pairing.data['sessionId']).toEqual(expect.any(String));
    expect(pairing.data['pairingToken']).toEqual(expect.any(String));

    const phone = await openSocket(address);
    const phoneRegistered = nextMessage(phone, 'registered');
    const pairedGameStatus = nextMessage(game, 'status');
    phone.send(
      JSON.stringify({
        event: 'register',
        data: {
          role: 'phone',
          version: 2,
          action: 'join',
          sessionId: pairing.data['sessionId'],
          pairingToken: pairing.data['pairingToken'],
        },
      }),
    );
    const phoneIdentity = await phoneRegistered;
    expect(phoneIdentity.data['generation']).toBe(1);
    expect(phoneIdentity.data['resumeToken']).toEqual(expect.any(String));
    expect((await pairedGameStatus).data).toMatchObject({
      phoneConnected: true,
      controllerStage: 'checking',
    });

    const disconnectedStatus = nextMessage(game, 'status');
    phone.close();
    expect((await disconnectedStatus).data).toMatchObject({
      phoneConnected: false,
      controllerStage: 'lost',
    });

    const resumedPhone = await openSocket(address);
    const resumedRegistration = nextMessage(resumedPhone, 'registered');
    const resumedStatus = nextMessage(game, 'status');
    resumedPhone.send(
      JSON.stringify({
        event: 'register',
        data: {
          role: 'phone',
          version: 2,
          action: 'resume',
          sessionId: pairing.data['sessionId'],
          resumeToken: phoneIdentity.data['resumeToken'],
        },
      }),
    );
    const resumedIdentity = await resumedRegistration;
    expect(resumedIdentity.data['generation']).toBe(2);
    expect(resumedIdentity.data['resumeToken']).not.toBe(
      phoneIdentity.data['resumeToken'],
    );
    expect((await resumedStatus).data).toMatchObject({
      phoneConnected: true,
      controllerStage: 'checking',
    });

    const sessionEnded = nextMessage(resumedPhone, 'session_ended');
    game.send(JSON.stringify({ event: 'session_end', data: {} }));
    await sessionEnded;
    resumedPhone.close();
    game.close();
  });

  it('routes v3 phones to their selected red and blue room slots', async () => {
    const game = await openSocket(address);
    const p1 = await openSocket(address);
    const p2 = await openSocket(address);
    try {
      const gameRegistered = nextMessage(game, 'registered');
      game.send(
        JSON.stringify({
          event: 'register',
          data: { role: 'game', version: 3, action: 'create' },
        }),
      );
      const registration = (await gameRegistered).data;
      expect(registration['version']).toBe(3);
      expect(registration['invites']).toHaveLength(1);

      const p1Registered = nextMessage(p1, 'registered');
      p1.send(
        JSON.stringify({
          event: 'register',
          data: {
            role: 'phone',
            version: 3,
            action: 'join',
            roomId: registration['roomId'],
            slotId: 'p1',
            pairingToken: (registration['invites'] as Array<Record<string, unknown>>)[0]?.['pairingToken'],
          },
        }),
      );
      const p1Identity = (await p1Registered).data;
      expect(p1Identity).toMatchObject({ slotId: 'p1', player: 'red' });

      const p2Invite = nextMessage(game, 'slot_invite');
      const configured = nextMessage(game, 'slot_configured');
      game.send(
        JSON.stringify({
          event: 'slot_config',
          data: {
            roomId: registration['roomId'],
            slotId: 'p2',
            source: 'phone',
            requestId: 'p2-phone',
          },
        }),
      );
      expect((await configured).data['requestId']).toBe('p2-phone');
      const invite = (await p2Invite).data;
      const p2Registered = nextMessage(p2, 'registered');
      p2.send(
        JSON.stringify({
          event: 'register',
          data: {
            role: 'phone',
            version: 3,
            action: 'join',
            roomId: registration['roomId'],
            slotId: invite['slotId'],
            pairingToken: invite['pairingToken'],
          },
        }),
      );
      const p2Identity = (await p2Registered).data;
      expect(p2Identity).toMatchObject({ slotId: 'p2', player: 'blue' });

      for (const [phone, identity, slotId] of [
        [p1, p1Identity, 'p1'],
        [p2, p2Identity, 'p2'],
      ] as const) {
        const relayed = nextMessage(game, 'input');
        phone.send(
          JSON.stringify({
            event: 'input',
            data: {
              roomId: registration['roomId'],
              slotId,
              generation: identity['generation'],
              seq: 0,
              steering: 0,
              throttle: 1,
              reverse: 0,
              brake: 0,
            },
          }),
        );
        expect((await relayed).data['slotId']).toBe(slotId);
      }

      const p2Collision = nextMessage(p2, 'collision');
      game.send(
        JSON.stringify({
          event: 'collision',
          data: {
            roomId: registration['roomId'],
            slotId: 'p2',
            generation: p2Identity['generation'],
          },
        }),
      );
      expect((await p2Collision).data['slotId']).toBe('p2');
      game.send(
        JSON.stringify({
          event: 'room_close',
          data: { roomId: registration['roomId'] },
        }),
      );
    } finally {
      p1.close();
      p2.close();
      game.close();
    }
  });
});
