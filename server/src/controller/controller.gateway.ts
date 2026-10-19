import type { IncomingMessage } from 'node:http';
import { performance } from 'node:perf_hooks';
import { OnModuleDestroy, Optional } from '@nestjs/common';
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
import {
  PairingSessionService,
  type ControllerStage,
  type PairingSession,
} from './pairing-session.service.js';

function verifyControllerOrigin(info: {
  origin: string;
  req: IncomingMessage;
}): boolean {
  const rawOrigin = info.origin || info.req.headers.origin;
  const origin = Array.isArray(rawOrigin) ? rawOrigin[0] : rawOrigin;
  return !origin || allowedControllerOrigins().has(origin);
}

interface SocketContext {
  role: ControllerRole;
  version: 1 | 2;
  sessionId?: string;
}

interface PairingSockets {
  game?: WebSocket;
  phone?: WebSocket;
  lastCollisionAtMs: number;
}

@WebSocketGateway({
  path: '/controller',
  maxPayload: 4096,
  verifyClient: verifyControllerOrigin,
})
export class ControllerGateway
  implements OnGatewayDisconnect<WebSocket>, OnModuleDestroy
{
  // Version 1 remains the single shared prototype relay. Version 2 sessions
  // are isolated and can coexist without claiming either global role.
  private readonly clients = new Map<ControllerRole, WebSocket>();
  private readonly contexts = new WeakMap<WebSocket, SocketContext>();
  private readonly generations = new WeakMap<WebSocket, number>();
  private readonly pairingSockets = new Map<string, PairingSockets>();
  private generation = 0;
  private lastSequence = -1;
  private rateWindowStarted = 0;
  private rateCount = 0;
  private lastCollisionAtMs = Number.NEGATIVE_INFINITY;
  private lastPhoneActivityMs = 0;
  private readonly maintenanceTimer = setInterval(
    () => this.maintainSessions(),
    1000,
  );
  private readonly phoneWatchdog = setInterval(
    () => this.watchLegacyPhone(),
    1000,
  );
  private readonly pairings: PairingSessionService;

  constructor(@Optional() pairingSessions?: PairingSessionService) {
    this.pairings = pairingSessions ?? new PairingSessionService();
    this.maintenanceTimer.unref();
    this.phoneWatchdog.unref();
  }

  onModuleDestroy(): void {
    clearInterval(this.maintenanceTimer);
    clearInterval(this.phoneWatchdog);
    for (const session of this.pairings.values()) {
      this.endPairingSession(session, 'relay_stopped');
    }
  }

  handleDisconnect(client: WebSocket): void {
    const context = this.contexts.get(client);
    if (!context) return;
    if (context.version === 1) {
      if (this.clients.get(context.role) !== client) return;
      this.clients.delete(context.role);
      if (context.role === 'phone') {
        this.broadcastLegacyGame('status', { phoneConnected: false });
        this.lastSequence = -1;
      }
      return;
    }

    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (!session || !sockets) return;
    if (context.role === 'game' && sockets.game === client) {
      this.endPairingSession(session, 'session_ended');
    } else if (context.role === 'phone' && sockets.phone === client) {
      delete sockets.phone;
      this.pairings.phoneDisconnected(session);
      this.sendPairingStatus(session);
    }
  }

  @SubscribeMessage('register')
  onRegister(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const registration = this.asRecord(data);
    const version = registration?.['version'];
    if (
      !registration ||
      !isRole(registration['role']) ||
      (version !== 1 && version !== 2)
    ) {
      this.reject(client, 'invalid registration');
      return;
    }
    if (this.contexts.has(client)) {
      this.reject(client, 'already registered');
      return;
    }
    if (version === 1) {
      this.registerLegacy(client, registration['role']);
      return;
    }
    this.registerPaired(client, registration);
  }

  @SubscribeMessage('input')
  onInput(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    if (context?.role !== 'phone' || !isControllerInput(data)) return;
    if (context.version === 1) {
      if (!this.withinLegacyRateLimit() || data.seq <= this.lastSequence)
        return;
      this.lastSequence = data.seq;
      this.lastPhoneActivityMs = performance.now();
      this.broadcastLegacyGame('input', {
        ...data,
        generation: this.generations.get(client),
      });
      return;
    }

    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (
      !session ||
      !sockets ||
      sockets.phone !== client ||
      !this.pairings.acceptInputRate(session) ||
      data.seq <= session.sequence
    ) {
      return;
    }
    session.sequence = data.seq;
    this.pairings.markPhoneActivity(session);
    if (session.controllerStage === 'checking') {
      session.controllerStage = 'ready';
      this.sendPairingStatus(session);
    }
    this.sendTo(sockets.game, 'input', {
      ...data,
      generation: session.generation,
    });
  }

  @SubscribeMessage('unavailable')
  onUnavailable(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    if (context?.role !== 'phone') return;
    const reason =
      this.asRecord(data)?.['reason'] === 'sensor' ? 'sensor' : 'phone';
    if (context.version === 1) {
      this.lastPhoneActivityMs = performance.now();
      this.broadcastLegacyGame('unavailable', {
        reason,
        generation: this.generations.get(client),
      });
      return;
    }
    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (!session || sockets?.phone !== client) return;
    this.pairings.markPhoneActivity(session);
    session.controllerStage = 'lost';
    this.sendTo(sockets.game, 'unavailable', {
      reason,
      generation: session.generation,
    });
    this.sendPairingStatus(session);
  }

  @SubscribeMessage('controller_state')
  onControllerState(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    if (context?.version !== 2 || context.role !== 'phone') return;
    const stage = this.asRecord(data)?.['stage'];
    if (!this.isControllerStage(stage)) return;
    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (!session || sockets?.phone !== client) return;
    this.pairings.markPhoneActivity(session);
    session.controllerStage = stage;
    this.sendPairingStatus(session);
  }

  @SubscribeMessage('collision')
  onCollision(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    const generation = record?.['generation'];
    if (context?.role !== 'game' || !Number.isSafeInteger(generation)) return;
    if (context.version === 1) {
      const phone = this.clients.get('phone');
      if (
        this.clients.get('game') !== client ||
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
      return;
    }
    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (
      !session ||
      !sockets ||
      sockets.game !== client ||
      sockets.phone?.readyState !== sockets.phone?.OPEN ||
      session.generation !== generation
    ) {
      return;
    }
    const now = performance.now();
    if (now - sockets.lastCollisionAtMs < 250) return;
    sockets.lastCollisionAtMs = now;
    this.send(sockets.phone, 'collision', { generation });
  }

  @SubscribeMessage('session_end')
  onSessionEnd(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() _data: unknown,
  ): void {
    const context = this.contexts.get(client);
    if (context?.version !== 2 || context.role !== 'game') return;
    const session = this.pairings.get(context.sessionId);
    if (session) this.endPairingSession(session, 'session_ended');
  }

  @SubscribeMessage('ping')
  onPing(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    if (!context) return;
    if (context.version === 1) {
      if (context.role === 'phone')
        this.lastPhoneActivityMs = performance.now();
    } else {
      const session = this.pairings.get(context.sessionId);
      if (!session) return;
      if (context.role === 'phone') this.pairings.markPhoneActivity(session);
      else this.pairings.markGameActivity(session);
    }
    this.send(client, 'pong', { id: this.asRecord(data)?.['id'] ?? null });
  }

  private registerLegacy(client: WebSocket, role: ControllerRole): void {
    const existing = this.clients.get(role);
    if (existing && existing.readyState === existing.OPEN) {
      this.send(client, 'error', { code: 'role_in_use' });
      client.close(1008, 'role already connected');
      return;
    }
    this.contexts.set(client, { role, version: 1 });
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
      this.broadcastLegacyGame('status', {
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

  private registerPaired(
    client: WebSocket,
    registration: Record<string, unknown>,
  ): void {
    const role = registration['role'] as ControllerRole;
    const action = registration['action'];
    if (role === 'game' && action === 'create') {
      const session = this.pairings.create();
      this.pairingSockets.set(session.id, {
        game: client,
        lastCollisionAtMs: Number.NEGATIVE_INFINITY,
      });
      this.contexts.set(client, { role, version: 2, sessionId: session.id });
      this.pairings.markGameActivity(session);
      this.send(client, 'registered', {
        role,
        sessionId: session.id,
        pairingToken: session.pairingToken,
        expiresAt: session.pairingExpiresAt,
      });
      this.sendPairingStatus(session);
      return;
    }
    if (role !== 'phone' || (action !== 'join' && action !== 'resume')) {
      this.reject(client, 'invalid v2 registration action');
      return;
    }
    const existingSession = this.pairings.get(registration['sessionId']);
    if (action === 'resume' && existingSession?.phoneConnected) {
      this.send(client, 'error', { code: 'resume_pending' });
      client.close(1008, 'previous phone connection is still active');
      return;
    }
    const result =
      action === 'join'
        ? this.pairings.join(
            registration['sessionId'],
            registration['pairingToken'],
          )
        : this.pairings.resume(
            registration['sessionId'],
            registration['resumeToken'],
          );
    if (!result.ok) {
      this.send(client, 'error', { code: result.code });
      client.close(1008, result.code);
      return;
    }
    const session = result.session;
    const sockets = this.pairingSockets.get(session.id);
    if (
      !sockets ||
      !sockets.game ||
      sockets.game.readyState !== sockets.game.OPEN
    ) {
      this.pairings.end(session);
      this.send(client, 'error', { code: 'session_ended' });
      client.close(1008, 'session ended');
      return;
    }
    sockets.phone = client;
    this.contexts.set(client, { role, version: 2, sessionId: session.id });
    this.send(client, 'registered', {
      role,
      sessionId: session.id,
      generation: session.generation,
      resumeToken: result.credential,
    });
    this.sendPairingStatus(session);
  }

  private watchLegacyPhone(): void {
    const phone = this.clients.get('phone');
    if (
      phone &&
      phone.readyState === phone.OPEN &&
      performance.now() - this.lastPhoneActivityMs > 4000
    ) {
      phone.close(1001, 'phone heartbeat timeout');
    }
  }

  private maintainSessions(): void {
    const now = Date.now();
    for (const session of this.pairings.values()) {
      if (session.phoneConnected && now - session.lastPhoneActivityAt > 4000) {
        const phone = this.pairingSockets.get(session.id)?.phone;
        phone?.close(1001, 'phone heartbeat timeout');
      }
      if (now - session.lastGameActivityAt > 4000) {
        this.endPairingSession(session, 'session_ended');
        continue;
      }
      if (this.pairings.expired(session, now)) {
        this.endPairingSession(
          session,
          now >= session.pairingExpiresAt && session.resumeExpiresAt === null
            ? 'pairing_expired'
            : 'session_ended',
        );
      }
    }
  }

  private sendPairingStatus(session: PairingSession): void {
    const sockets = this.pairingSockets.get(session.id);
    const status = {
      phoneConnected: session.phoneConnected,
      generation: session.generation,
      controllerStage: session.controllerStage,
    };
    this.send(sockets?.game, 'status', status);
    this.send(sockets?.phone, 'status', status);
  }

  private endPairingSession(session: PairingSession, code: string): void {
    if (session.ended) return;
    const sockets = this.pairingSockets.get(session.id);
    this.send(sockets?.phone, 'session_ended', { code });
    this.send(sockets?.game, 'session_ended', { code });
    sockets?.game?.close(1000, code);
    sockets?.phone?.close(1000, code);
    this.pairingSockets.delete(session.id);
    this.pairings.end(session);
  }

  private withinLegacyRateLimit(): boolean {
    const now = Date.now();
    if (now - this.rateWindowStarted >= 1000) {
      this.rateWindowStarted = now;
      this.rateCount = 0;
    }
    this.rateCount++;
    return this.rateCount <= 60;
  }

  private broadcastLegacyGame(
    event: string,
    data: Record<string, unknown>,
  ): void {
    const game = this.clients.get('game');
    if (game && game.readyState === game.OPEN) this.send(game, event, data);
  }

  private sendTo(
    client: WebSocket | undefined,
    event: string,
    data: Record<string, unknown>,
  ): void {
    if (client) this.send(client, event, data);
  }

  private send(
    client: WebSocket | undefined,
    event: string,
    data: Record<string, unknown>,
  ): void {
    if (client && client.readyState === client.OPEN) {
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

  private isControllerStage(value: unknown): value is ControllerStage {
    return (
      value === 'checking' ||
      value === 'calibrating' ||
      value === 'ready' ||
      value === 'lost'
    );
  }
}
