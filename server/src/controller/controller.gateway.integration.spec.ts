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
});
