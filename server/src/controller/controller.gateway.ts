import type { IncomingMessage } from 'node:http';
import { performance } from 'node:perf_hooks';
import { OnModuleDestroy } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import type { OnGatewayDisconnect } from '@nestjs/websockets';
import type { WebSocket } from 'ws';

import {
  allowedControllerOrigins,
  isControllerInput,
  isRole,
  type ControllerRole,
} from './controller.protocol.js';

function verifyControllerOrigin(info: {
  origin: string;
  req: IncomingMessage;
}): boolean {
  const rawOrigin = info.origin || info.req.headers.origin;
  const origin = Array.isArray(rawOrigin) ? rawOrigin[0] : rawOrigin;
  return !origin || allowedControllerOrigins().has(origin);
}

@WebSocketGateway({
  path: '/controller',
  maxPayload: 4096,
  verifyClient: verifyControllerOrigin,
})
export class ControllerGateway
  implements OnGatewayDisconnect<WebSocket>, OnModuleDestroy
{
  private readonly clients = new Map<ControllerRole, WebSocket>();
  private readonly roles = new WeakMap<WebSocket, ControllerRole>();
  private readonly generations = new WeakMap<WebSocket, number>();
  private generation = 0;
  private lastSequence = -1;
  private rateWindowStarted = 0;
  private rateCount = 0;
  private lastCollisionAtMs = Number.NEGATIVE_INFINITY;
  private lastPhoneActivityMs = 0;
  private readonly phoneWatchdog = setInterval(() => {
    const phone = this.clients.get('phone');
    if (
      phone &&
      phone.readyState === phone.OPEN &&
      performance.now() - this.lastPhoneActivityMs > 4000
    ) {
      phone.close(1001, 'phone heartbeat timeout');
    }
  }, 1000);

  constructor() {
    this.phoneWatchdog.unref();
  }

  onModuleDestroy(): void {
    clearInterval(this.phoneWatchdog);
  }

  handleDisconnect(client: WebSocket): void {
    const role = this.roles.get(client);
    if (!role || this.clients.get(role) !== client) return;
    this.clients.delete(role);
    if (role === 'phone')
      this.broadcastGame('status', { phoneConnected: false });
    if (role === 'phone') {
      this.lastSequence = -1;
    }
  }

  @SubscribeMessage('register')
  onRegister(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const registration = this.asRecord(data);
    if (
      !registration ||
      !isRole(registration['role']) ||
      registration['version'] !== 1
    ) {
      this.reject(client, 'invalid registration');
      return;
    }
    if (this.roles.has(client)) {
      this.reject(client, 'already registered');
      return;
    }
    const role = registration['role'];
    const existing = this.clients.get(role);
    if (existing && existing.readyState === existing.OPEN) {
      this.send(client, 'error', { code: 'role_in_use' });
      client.close(1008, 'role already connected');
      return;
    }

    this.roles.set(client, role);
    this.clients.set(role, client);
    let phoneGeneration: number | undefined;
    if (role === 'phone') {
      phoneGeneration = ++this.generation;
      this.generations.set(client, phoneGeneration);
      this.lastSequence = -1;
      this.lastPhoneActivityMs = performance.now();
    }
    this.send(client, 'registered', {
      role,
      ...(phoneGeneration === undefined ? {} : { generation: phoneGeneration }),
    });
    if (role === 'phone') {
      this.broadcastGame('status', {
        phoneConnected: true,
        generation: phoneGeneration,
      });
    } else {
      const phone = this.clients.get('phone');
      this.send(client, 'status', {
        phoneConnected: Boolean(phone && phone.readyState === phone.OPEN),
        ...(phone ? { generation: this.generations.get(phone) } : {}),
      });
    }
  }

  @SubscribeMessage('input')
  onInput(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    if (this.roles.get(client) !== 'phone' || !isControllerInput(data)) return;
    if (!this.withinRateLimit() || data.seq <= this.lastSequence) return;
    this.lastSequence = data.seq;
    this.lastPhoneActivityMs = performance.now();
    this.broadcastGame('input', {
      ...data,
      generation: this.generations.get(client),
    });
  }

  @SubscribeMessage('unavailable')
  onUnavailable(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    if (this.roles.get(client) !== 'phone') return;
    this.lastPhoneActivityMs = performance.now();
    this.broadcastGame('unavailable', {
      reason: this.asRecord(data)?.['reason'] === 'sensor' ? 'sensor' : 'phone',
      generation: this.generations.get(client),
    });
  }

  @SubscribeMessage('collision')
  onCollision(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const record = this.asRecord(data);
    const phone = this.clients.get('phone');
    const generation = record?.['generation'];
    if (
      this.roles.get(client) !== 'game' ||
      this.clients.get('game') !== client ||
      !Number.isSafeInteger(generation) ||
      !phone ||
      phone.readyState !== phone.OPEN ||
      this.generations.get(phone) !== generation
    ) {
      return;
    }
    const now = performance.now();
    if (now - this.lastCollisionAtMs < 250) return;
    this.lastCollisionAtMs = now;
    this.send(phone, 'collision', { generation });
  }

  @SubscribeMessage('ping')
  onPing(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    if (!this.roles.has(client)) return;
    if (this.roles.get(client) === 'phone') {
      this.lastPhoneActivityMs = performance.now();
    }
    this.send(client, 'pong', { id: this.asRecord(data)?.['id'] ?? null });
  }

  private withinRateLimit(): boolean {
    const now = Date.now();
    if (now - this.rateWindowStarted >= 1000) {
      this.rateWindowStarted = now;
      this.rateCount = 0;
    }
    this.rateCount++;
    return this.rateCount <= 60;
  }

  private broadcastGame(event: string, data: Record<string, unknown>): void {
    const game = this.clients.get('game');
    if (game && game.readyState === game.OPEN) this.send(game, event, data);
  }

  private send(
    client: WebSocket,
    event: string,
    data: Record<string, unknown>,
  ): void {
    if (client.readyState === client.OPEN) {
      client.send(JSON.stringify({ event, data }));
    }
  }

  private reject(client: WebSocket, reason: string): void {
    this.send(client, 'error', { code: 'invalid_message', reason });
    client.close(1008, reason);
  }

  private asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  }
}
