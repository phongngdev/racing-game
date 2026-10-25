import { randomBytes, randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';

export type RoomSlotId = 'p1' | 'p2';
export type RoomSource = 'phone' | 'keyboard';
export type RoomStage = 'checking' | 'calibrating' | 'ready' | 'lost';

export interface RoomSlot {
  readonly id: RoomSlotId;
  readonly player: 'red' | 'blue';
  source: RoomSource;
  pairingToken: string | null;
  pairingExpiresAt: number | null;
  resumeToken: string | null;
  resumeExpiresAt: number | null;
  generation: number;
  sequence: number;
  connected: boolean;
  stage: RoomStage;
  lastActivityAt: number;
  rateWindowStartedAt: number;
  rateCount: number;
}

export interface MultiplayerRoom {
  readonly id: string;
  readonly createdAt: number;
  lastHostActivityAt: number;
  ended: boolean;
  readonly slots: Record<RoomSlotId, RoomSlot>;
}

export type RoomResult =
  | { ok: true; room: MultiplayerRoom; slot?: RoomSlot; credential?: string }
  | { ok: false; code: string };

@Injectable()
export class MultiplayerRoomService {
  static readonly inviteLifetimeMs = 5 * 60 * 1000;
  static readonly resumeLifetimeMs = 30 * 1000;

  private readonly rooms = new Map<string, MultiplayerRoom>();

  create(now = Date.now()): MultiplayerRoom {
    const room: MultiplayerRoom = {
      id: randomUUID(),
      createdAt: now,
      lastHostActivityAt: now,
      ended: false,
      slots: {
        p1: this.newSlot('p1', 'red', 'phone', now),
        p2: this.newSlot('p2', 'blue', 'keyboard', now),
      },
    };
    this.rooms.set(room.id, room);
    return room;
  }

  get(id: unknown): MultiplayerRoom | undefined {
    return typeof id === 'string' ? this.rooms.get(id) : undefined;
  }

  join(
    roomId: unknown,
    slotId: unknown,
    token: unknown,
    now = Date.now(),
  ): RoomResult {
    const room = this.get(roomId);
    if (!room || room.ended) return { ok: false, code: 'room_closed' };
    const slot = this.slot(room, slotId);
    if (!slot || slot.source !== 'phone')
      return { ok: false, code: 'slot_not_phone' };
    if (slot.connected) return { ok: false, code: 'slot_in_use' };
    if (slot.resumeToken !== null) {
      if (slot.resumeExpiresAt !== null && now > slot.resumeExpiresAt) {
        this.release(slot);
      } else {
        return { ok: false, code: 'slot_reserved' };
      }
    }
    if (
      slot.pairingToken === null ||
      slot.pairingExpiresAt === null ||
      now >= slot.pairingExpiresAt
    ) {
      slot.pairingToken = null;
      slot.pairingExpiresAt = null;
      return { ok: false, code: 'pairing_expired' };
    }
    if (typeof token !== 'string' || token !== slot.pairingToken) {
      return { ok: false, code: 'invalid_pairing' };
    }
    slot.pairingToken = null;
    slot.pairingExpiresAt = null;
    slot.resumeToken = this.token();
    slot.resumeExpiresAt = null;
    slot.generation++;
    slot.sequence = -1;
    slot.connected = true;
    slot.stage = 'checking';
    slot.lastActivityAt = now;
    return { ok: true, room, slot, credential: slot.resumeToken };
  }

  resume(
    roomId: unknown,
    slotId: unknown,
    token: unknown,
    now = Date.now(),
  ): RoomResult {
    const room = this.get(roomId);
    if (!room || room.ended) return { ok: false, code: 'room_closed' };
    const slot = this.slot(room, slotId);
    if (!slot || slot.source !== 'phone')
      return { ok: false, code: 'slot_not_phone' };
    if (slot.connected) return { ok: false, code: 'resume_pending' };
    if (
      typeof token !== 'string' ||
      token !== slot.resumeToken ||
      slot.resumeExpiresAt === null ||
      now > slot.resumeExpiresAt
    ) {
      return { ok: false, code: 'resume_expired' };
    }
    slot.resumeExpiresAt = null;
    slot.generation++;
    slot.sequence = -1;
    slot.connected = true;
    slot.stage = 'checking';
    slot.lastActivityAt = now;
    return { ok: true, room, slot, credential: slot.resumeToken };
  }

  disconnected(slot: RoomSlot, now = Date.now()): void {
    if (!slot.connected) return;
    slot.connected = false;
    slot.stage = 'lost';
    slot.sequence = -1;
    slot.resumeExpiresAt = now + MultiplayerRoomService.resumeLifetimeMs;
  }

  leave(slot: RoomSlot): void {
    this.release(slot);
    this.issueInvite(slot);
  }

  configure(
    room: MultiplayerRoom,
    slot: RoomSlot,
    source: RoomSource,
    now = Date.now(),
  ): void {
    this.release(slot);
    slot.source = source;
    if (source === 'phone') this.issueInvite(slot, now);
    else {
      slot.pairingToken = null;
      slot.pairingExpiresAt = null;
    }
    room.lastHostActivityAt = now;
  }

  resetSlot(room: MultiplayerRoom, slot: RoomSlot, now = Date.now()): string {
    this.release(slot);
    return this.issueInvite(slot, now);
  }

  markSlotActivity(slot: RoomSlot, now = Date.now()): void {
    slot.lastActivityAt = now;
  }

  acceptInputRate(slot: RoomSlot, now = Date.now()): boolean {
    if (now - slot.rateWindowStartedAt >= 1000) {
      slot.rateWindowStartedAt = now;
      slot.rateCount = 0;
    }
    return ++slot.rateCount <= 60;
  }

  expiredResumeSlots(room: MultiplayerRoom, now = Date.now()): RoomSlot[] {
    const expired: RoomSlot[] = [];
    for (const slot of Object.values(room.slots)) {
      if (
        !slot.connected &&
        slot.resumeToken !== null &&
        slot.resumeExpiresAt !== null &&
        now > slot.resumeExpiresAt
      ) {
        this.release(slot);
        this.issueInvite(slot, now);
        expired.push(slot);
      }
    }
    return expired;
  }

  end(room: MultiplayerRoom): void {
    if (room.ended) return;
    room.ended = true;
    for (const slot of Object.values(room.slots)) this.release(slot);
    this.rooms.delete(room.id);
  }

  values(): IterableIterator<MultiplayerRoom> {
    return this.rooms.values();
  }

  snapshot(room: MultiplayerRoom): Record<string, unknown> {
    return {
      roomId: room.id,
      slots: Object.values(room.slots).map((slot) => ({
        slotId: slot.id,
        player: slot.player,
        source: slot.source,
        connected: slot.connected,
        generation: slot.generation,
        stage: slot.stage,
        reservedUntil: slot.resumeExpiresAt,
        inviteExpiresAt: slot.pairingExpiresAt,
      })),
    };
  }

  private slot(room: MultiplayerRoom, id: unknown): RoomSlot | undefined {
    return id === 'p1' || id === 'p2' ? room.slots[id] : undefined;
  }

  private release(slot: RoomSlot): void {
    slot.connected = false;
    slot.stage = 'lost';
    slot.sequence = -1;
    slot.resumeToken = null;
    slot.resumeExpiresAt = null;
    slot.pairingToken = null;
    slot.pairingExpiresAt = null;
    slot.generation++;
  }

  private issueInvite(slot: RoomSlot, now = Date.now()): string {
    slot.pairingToken = this.token();
    slot.pairingExpiresAt = now + MultiplayerRoomService.inviteLifetimeMs;
    return slot.pairingToken;
  }

  private newSlot(
    id: RoomSlotId,
    player: 'red' | 'blue',
    source: RoomSource,
    now: number,
  ): RoomSlot {
    return {
      id,
      player,
      source,
      pairingToken: source === 'phone' ? this.token() : null,
      pairingExpiresAt:
        source === 'phone' ? now + MultiplayerRoomService.inviteLifetimeMs : null,
      resumeToken: null,
      resumeExpiresAt: null,
      generation: 0,
      sequence: -1,
      connected: false,
      stage: 'lost',
      lastActivityAt: now,
      rateWindowStartedAt: now,
      rateCount: 0,
    };
  }

  private token(): string {
    return randomBytes(24).toString('base64url');
  }
}
