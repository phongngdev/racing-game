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
  isMultiplayerSlot,
  isMultiplayerSource,
  isProtocolVersion,
  isRole,
  type MultiplayerSlotId,
  type MultiplayerSource,
  type ControllerRole,
} from './controller.protocol.js';
import {
  PairingSessionService,
  type ControllerStage,
  type PairingSession,
} from './pairing-session.service.js';
import {
  MultiplayerRoomService,
  type MultiplayerRoom,
  type RoomSlot,
} from './multiplayer-room.service.js';

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
  version: 1 | 2 | 3;
  sessionId?: string;
  roomId?: string;
  slotId?: MultiplayerSlotId;
}

interface PairingSockets {
  game?: WebSocket;
  phone?: WebSocket;
  lastCollisionAtMs: number;
}

interface RoomSockets {
  game?: WebSocket;
  phones: Map<MultiplayerSlotId, WebSocket>;
  lastCollisionAtMs: Map<MultiplayerSlotId, number>;
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
  private readonly roomSockets = new Map<string, RoomSockets>();
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
  private readonly rooms: MultiplayerRoomService;

  constructor(
    @Optional() pairingSessions?: PairingSessionService,
    @Optional() multiplayerRooms?: MultiplayerRoomService,
  ) {
    this.pairings = pairingSessions ?? new PairingSessionService();
    this.rooms = multiplayerRooms ?? new MultiplayerRoomService();
    this.maintenanceTimer.unref();
    this.phoneWatchdog.unref();
  }

  onModuleDestroy(): void {
    clearInterval(this.maintenanceTimer);
    clearInterval(this.phoneWatchdog);
    for (const session of this.pairings.values()) {
      this.endPairingSession(session, 'relay_stopped');
    }
    for (const room of this.rooms.values()) this.endRoom(room, 'relay_stopped');
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

    if (context.version === 3) {
      const room = this.rooms.get(context.roomId);
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      if (!room || !sockets) return;
      if (context.role === 'game' && sockets.game === client) {
        this.endRoom(room, 'room_closed');
      } else if (
        context.role === 'phone' &&
        context.slotId &&
        sockets.phones.get(context.slotId) === client
      ) {
        sockets.phones.delete(context.slotId);
        this.rooms.disconnected(room.slots[context.slotId]);
        this.sendRoomState(room);
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
      !isProtocolVersion(version)
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
    if (version === 2) this.registerPaired(client, registration);
    else this.registerRoom(client, registration);
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

    if (context.version === 3) {
      this.routeRoomInput(client, context, { ...data });
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
    if (context.version === 3) {
      const record = this.asRecord(data);
      const room = this.rooms.get(context.roomId);
      const slot = context.slotId && room?.slots[context.slotId];
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      if (
        !room ||
        !slot ||
        !sockets ||
        sockets.phones.get(slot.id) !== client ||
        record?.['generation'] !== slot.generation
      ) {
        return;
      }
      const reason = record['reason'] === 'sensor' ? 'sensor' : 'phone';
      slot.stage = 'lost';
      this.rooms.markSlotActivity(slot);
      this.sendTo(sockets.game, 'unavailable', {
        roomId: room.id,
        slotId: slot.id,
        reason,
        generation: slot.generation,
      });
      this.sendRoomState(room);
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
    const stage = this.asRecord(data)?.['stage'];
    if (!this.isControllerStage(stage)) return;
    if (context?.version === 3 && context.role === 'phone') {
      const record = this.asRecord(data);
      const room = this.rooms.get(context.roomId);
      const slot = context.slotId && room?.slots[context.slotId];
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      if (
        !room ||
        !slot ||
        !sockets ||
        sockets.phones.get(slot.id) !== client ||
        record?.['generation'] !== slot.generation
      ) {
        return;
      }
      slot.stage = stage;
      this.rooms.markSlotActivity(slot);
      this.sendRoomState(room);
      return;
    }
    if (context?.version !== 2 || context.role !== 'phone') return;
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
    const payload = {
      generation,
      ...this.validCollisionIntensity(record?.['intensity']),
    };
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
      this.send(phone, 'collision', payload);
      return;
    }
    if (context.version === 3) {
      const slotId = record?.['slotId'];
      if (!isMultiplayerSlot(slotId) || record?.['roomId'] !== context.roomId)
        return;
      const room = this.rooms.get(context.roomId);
      const slot = room?.slots[slotId];
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      const phone = sockets?.phones.get(slotId);
      if (
        !room ||
        !slot ||
        sockets?.game !== client ||
        !phone ||
        phone.readyState !== phone.OPEN ||
        slot.generation !== generation ||
        !slot.connected
      ) {
        return;
      }
      const now = performance.now();
      if (now - (sockets.lastCollisionAtMs.get(slotId) ?? Number.NEGATIVE_INFINITY) < 250)
        return;
      sockets.lastCollisionAtMs.set(slotId, now);
      this.send(phone, 'collision', {
        roomId: room.id,
        slotId,
        ...payload,
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
      sockets.game !== client ||
      sockets.phone?.readyState !== sockets.phone?.OPEN ||
      session.generation !== generation
    ) {
      return;
    }
    const now = performance.now();
    if (now - sockets.lastCollisionAtMs < 250) return;
    sockets.lastCollisionAtMs = now;
    this.send(sockets.phone, 'collision', payload);
  }

  @SubscribeMessage('haptic')
  onHaptic(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    const generation = record?.['generation'];
    const event = record?.['event'];
    if (
      context?.role !== 'game' ||
      !Number.isSafeInteger(generation) ||
      !this.isHapticCue(event)
    ) return;

    if (context.version === 1) {
      const phone = this.clients.get('phone');
      if (
        this.clients.get('game') !== client ||
        !phone ||
        phone.readyState !== phone.OPEN ||
        this.generations.get(phone) !== generation
      ) return;
      this.send(phone, 'haptic', { generation, event });
      return;
    }
    if (context.version === 3) {
      const slotId = record?.['slotId'];
      if (!isMultiplayerSlot(slotId) || record?.['roomId'] !== context.roomId)
        return;
      const room = this.rooms.get(context.roomId);
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      const phone = sockets?.phones.get(slotId);
      const slot = room?.slots[slotId];
      if (
        !room || !slot || sockets?.game !== client || !phone ||
        phone.readyState !== phone.OPEN || slot.generation !== generation ||
        !slot.connected
      ) return;
      this.send(phone, 'haptic', { roomId: room.id, slotId, generation, event });
      return;
    }
    const session = this.pairings.get(context.sessionId);
    const sockets = context.sessionId
      ? this.pairingSockets.get(context.sessionId)
      : undefined;
    if (
      !session || !sockets || sockets.game !== client ||
      sockets.phone?.readyState !== sockets.phone?.OPEN ||
      session.generation !== generation
    ) return;
    this.send(sockets.phone, 'haptic', { generation, event });
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

  @SubscribeMessage('slot_config')
  onSlotConfig(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    const room = context?.version === 3 && context.role === 'game'
      ? this.rooms.get(context.roomId)
      : undefined;
    const sockets = context?.roomId
      ? this.roomSockets.get(context.roomId)
      : undefined;
    const slotId = record?.['slotId'];
    const source = record?.['source'];
    const requestId = record?.['requestId'];
    if (
      !room ||
      !sockets ||
      sockets.game !== client ||
      record?.['roomId'] !== room.id ||
      !isMultiplayerSlot(slotId) ||
      !isMultiplayerSource(source) ||
      typeof requestId !== 'string' ||
      requestId.length > 128
    ) {
      this.send(client, 'error', { code: 'invalid_message' });
      return;
    }
    const slot = room.slots[slotId];
    const oldPhone = sockets.phones.get(slotId);
    sockets.phones.delete(slotId);
    this.rooms.configure(room, slot, source as MultiplayerSource);
    oldPhone?.close(1000, 'slot_reconfigured');
    this.send(client, 'slot_configured', { requestId, slotId, source });
    if (source === 'phone') this.sendSlotInvite(room, slot);
    this.sendRoomState(room);
  }

  @SubscribeMessage('slot_reset')
  onSlotReset(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    const room = context?.version === 3 && context.role === 'game'
      ? this.rooms.get(context.roomId)
      : undefined;
    const sockets = context?.roomId
      ? this.roomSockets.get(context.roomId)
      : undefined;
    const slotId = record?.['slotId'];
    if (
      !room ||
      !sockets ||
      sockets.game !== client ||
      record?.['roomId'] !== room.id ||
      !isMultiplayerSlot(slotId)
    ) {
      this.send(client, 'error', { code: 'invalid_message' });
      return;
    }
    const slot = room.slots[slotId];
    if (slot.source !== 'phone') {
      this.send(client, 'error', { code: 'slot_not_phone' });
      return;
    }
    const oldPhone = sockets.phones.get(slotId);
    sockets.phones.delete(slotId);
    this.rooms.resetSlot(room, slot);
    oldPhone?.close(1000, 'slot_reset');
    this.sendSlotInvite(room, slot);
    this.sendRoomState(room);
  }

  @SubscribeMessage('slot_leave')
  onSlotLeave(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    if (
      context?.version !== 3 ||
      context.role !== 'phone' ||
      !context.slotId ||
      record?.['roomId'] !== context.roomId ||
      record?.['slotId'] !== context.slotId ||
      record?.['generation'] !== this.rooms.get(context.roomId)?.slots[context.slotId].generation
    ) {
      return;
    }
    const room = this.rooms.get(context.roomId);
    const sockets = this.roomSockets.get(context.roomId!);
    const slot = room?.slots[context.slotId];
    if (!room || !sockets || !slot || sockets.phones.get(slot.id) !== client)
      return;
    sockets.phones.delete(slot.id);
    this.rooms.leave(slot);
    this.send(client, 'slot_left', { roomId: room.id, slotId: slot.id });
    client.close(1000, 'slot_left');
    this.sendSlotInvite(room, slot);
    this.sendRoomState(room);
  }

  @SubscribeMessage('room_close')
  onRoomClose(
    @ConnectedSocket() client: WebSocket,
    @MessageBody() data: unknown,
  ): void {
    const context = this.contexts.get(client);
    const record = this.asRecord(data);
    if (context?.version !== 3 || context.role !== 'game') return;
    const room = this.rooms.get(context.roomId);
    const sockets = this.roomSockets.get(context.roomId!);
    if (
      room &&
      sockets?.game === client &&
      record?.['roomId'] === room.id
    ) {
      this.endRoom(room, 'room_closed');
    }
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
    } else if (context.version === 3) {
      const room = this.rooms.get(context.roomId);
      const sockets = context.roomId
        ? this.roomSockets.get(context.roomId)
        : undefined;
      if (!room || !sockets) return;
      if (context.role === 'game' && sockets.game === client) {
        room.lastHostActivityAt = Date.now();
      } else if (
        context.role === 'phone' &&
        context.slotId &&
        sockets.phones.get(context.slotId) === client
      ) {
        const slot = room.slots[context.slotId];
        this.rooms.markSlotActivity(slot);
      } else {
        return;
      }
    } else {
      const session = this.pairings.get(context.sessionId);
      if (!session) return;
      if (context.role === 'phone') this.pairings.markPhoneActivity(session);
      else this.pairings.markGameActivity(session);
    }
    this.send(client, 'pong', { id: this.asRecord(data)?.['id'] ?? null });
  }

  private registerRoom(
    client: WebSocket,
    registration: Record<string, unknown>,
  ): void {
    const role = registration['role'] as ControllerRole;
    const action = registration['action'];
    if (role === 'game' && action === 'create') {
      const room = this.rooms.create();
      const sockets: RoomSockets = {
        game: client,
        phones: new Map(),
        lastCollisionAtMs: new Map(),
      };
      this.roomSockets.set(room.id, sockets);
      this.contexts.set(client, { role, version: 3, roomId: room.id });
      room.lastHostActivityAt = Date.now();
      this.send(client, 'registered', {
        role,
        version: 3,
        roomId: room.id,
        invites: [this.invite(room.slots.p1)],
      });
      this.sendRoomState(room);
      return;
    }
    if (role !== 'phone' || (action !== 'join' && action !== 'resume')) {
      this.reject(client, 'invalid v3 registration action');
      return;
    }
    const slotId = registration['slotId'];
    const result = action === 'join'
      ? this.rooms.join(
          registration['roomId'],
          slotId,
          registration['pairingToken'],
        )
      : this.rooms.resume(
          registration['roomId'],
          slotId,
          registration['resumeToken'],
        );
    if (!result.ok) {
      this.send(client, 'error', { code: result.code });
      client.close(1008, result.code);
      return;
    }
    const { slot, credential } = result;
    const sockets = this.roomSockets.get(result.room.id);
    if (
      !slot ||
      !credential ||
      !sockets?.game ||
      sockets.game.readyState !== sockets.game.OPEN
    ) {
      this.rooms.leave(slot!);
      this.send(client, 'error', { code: 'room_closed' });
      client.close(1008, 'room closed');
      return;
    }
    sockets.phones.set(slot.id, client);
    this.contexts.set(client, {
      role,
      version: 3,
      roomId: result.room.id,
      slotId: slot.id,
    });
    this.send(client, 'registered', {
      role,
      version: 3,
      roomId: result.room.id,
      slotId: slot.id,
      player: slot.player,
      generation: slot.generation,
      resumeToken: credential,
    });
    this.sendRoomState(result.room);
  }

  private routeRoomInput(
    client: WebSocket,
    context: SocketContext,
    data: Record<string, unknown>,
  ): void {
    const room = this.rooms.get(context.roomId);
    const slot = context.slotId && room?.slots[context.slotId];
    const sockets = context.roomId
      ? this.roomSockets.get(context.roomId)
      : undefined;
    if (
      !room ||
      !slot ||
      !sockets ||
      sockets.phones.get(slot.id) !== client ||
      !slot.connected ||
      slot.source !== 'phone' ||
      data['roomId'] !== room.id ||
      data['slotId'] !== slot.id ||
      data['generation'] !== slot.generation ||
      !this.rooms.acceptInputRate(slot) ||
      (data['seq'] as number) <= slot.sequence
    ) {
      return;
    }
    slot.sequence = data['seq'] as number;
    this.rooms.markSlotActivity(slot);
    this.send(sockets.game, 'input', { ...data });
  }

  private invite(slot: RoomSlot): Record<string, unknown> | null {
    if (!slot.pairingToken || slot.pairingExpiresAt === null) return null;
    return {
      slotId: slot.id,
      pairingToken: slot.pairingToken,
      expiresAt: slot.pairingExpiresAt,
    };
  }

  private sendSlotInvite(room: MultiplayerRoom, slot: RoomSlot): void {
    const invite = this.invite(slot);
    if (invite) {
      this.send(this.roomSockets.get(room.id)?.game, 'slot_invite', {
        roomId: room.id,
        ...invite,
      });
    }
  }

  private sendRoomState(room: MultiplayerRoom): void {
    const sockets = this.roomSockets.get(room.id);
    const snapshot = this.rooms.snapshot(room);
    this.send(sockets?.game, 'room_state', snapshot);
    for (const phone of sockets?.phones.values() ?? []) {
      this.send(phone, 'room_state', snapshot);
    }
  }

  private endRoom(room: MultiplayerRoom, code: string): void {
    const sockets = this.roomSockets.get(room.id);
    if (!sockets) return;
    this.send(sockets.game, 'room_closed', { roomId: room.id, code });
    for (const phone of sockets.phones.values()) {
      this.send(phone, 'room_closed', { roomId: room.id, code });
      phone.close(1000, code);
    }
    sockets.game?.close(1000, code);
    this.roomSockets.delete(room.id);
    this.rooms.end(room);
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
    for (const room of this.rooms.values()) {
      const sockets = this.roomSockets.get(room.id);
      if (
        !sockets?.game ||
        sockets.game.readyState !== sockets.game.OPEN ||
        now - room.lastHostActivityAt > 4000
      ) {
        this.endRoom(room, 'room_closed');
        continue;
      }
      const expiredSlots = this.rooms.expiredResumeSlots(room, now);
      let changed = expiredSlots.length > 0;
      for (const slot of expiredSlots) this.sendSlotInvite(room, slot);
      for (const slot of Object.values(room.slots)) {
        const phone = sockets.phones.get(slot.id);
        if (slot.connected && now - slot.lastActivityAt > 4000) {
          if (phone) phone.close(1001, 'phone heartbeat timeout');
          else {
            this.rooms.disconnected(slot, now);
            changed = true;
          }
        }
        if (
          !slot.connected &&
          slot.resumeToken === null &&
          slot.pairingToken !== null &&
          slot.pairingExpiresAt !== null &&
          now >= slot.pairingExpiresAt
        ) {
          slot.pairingToken = null;
          slot.pairingExpiresAt = null;
          changed = true;
        }
      }
      if (changed) this.sendRoomState(room);
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

  private validCollisionIntensity(value: unknown): { intensity?: number } {
    if (typeof value !== 'number' || !Number.isFinite(value)) return {};
    return { intensity: Math.max(0, Math.min(1, value)) };
  }

  private isHapticCue(value: unknown): value is string {
    return (
      value === 'checkpoint' ||
      value === 'go' ||
      value === 'finish' ||
      value === 'victory' ||
      value === 'draw' ||
      value === 'dnf'
    );
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
