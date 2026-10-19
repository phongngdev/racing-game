import { randomBytes, randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';

export type ControllerStage = 'checking' | 'calibrating' | 'ready' | 'lost';

export interface PairingSession {
  readonly id: string;
  readonly pairingToken: string;
  readonly pairingExpiresAt: number;
  readonly createdAt: number;
  resumeToken: string | null;
  resumeExpiresAt: number | null;
  generation: number;
  sequence: number;
  phoneConnected: boolean;
  controllerStage: ControllerStage;
  lastPhoneActivityAt: number;
  lastGameActivityAt: number;
  inputRateWindowStartedAt: number;
  inputRateCount: number;
  ended: boolean;
}

export type PairingResult =
  | { ok: true; session: PairingSession; credential: string }
  | { ok: false; code: string };

@Injectable()
export class PairingSessionService {
  static readonly pairingLifetimeMs = 5 * 60 * 1000;
  static readonly phoneResumeLifetimeMs = 30 * 1000;

  private readonly sessions = new Map<string, PairingSession>();

  create(now = Date.now()): PairingSession {
    const session: PairingSession = {
      id: randomUUID(),
      pairingToken: this.token(),
      pairingExpiresAt: now + PairingSessionService.pairingLifetimeMs,
      createdAt: now,
      resumeToken: null,
      resumeExpiresAt: null,
      generation: 0,
      sequence: -1,
      phoneConnected: false,
      controllerStage: 'lost',
      lastPhoneActivityAt: now,
      lastGameActivityAt: now,
      inputRateWindowStartedAt: now,
      inputRateCount: 0,
      ended: false,
    };
    this.sessions.set(session.id, session);
    return session;
  }

  get(id: unknown): PairingSession | undefined {
    return typeof id === 'string' ? this.sessions.get(id) : undefined;
  }

  join(id: unknown, token: unknown, now = Date.now()): PairingResult {
    const session = this.get(id);
    if (!session || session.ended) return { ok: false, code: 'session_ended' };
    if (session.phoneConnected || session.resumeToken !== null) {
      return { ok: false, code: 'phone_already_joined' };
    }
    if (now >= session.pairingExpiresAt) {
      this.end(session);
      return { ok: false, code: 'pairing_expired' };
    }
    if (typeof token !== 'string' || token !== session.pairingToken) {
      return { ok: false, code: 'invalid_pairing' };
    }
    return this.attachPhone(session, now);
  }

  resume(id: unknown, token: unknown, now = Date.now()): PairingResult {
    const session = this.get(id);
    if (!session || session.ended) return { ok: false, code: 'session_ended' };
    if (
      typeof token !== 'string' ||
      token !== session.resumeToken ||
      session.resumeExpiresAt === null ||
      now > session.resumeExpiresAt
    ) {
      return { ok: false, code: 'resume_expired' };
    }
    if (session.phoneConnected) {
      return { ok: false, code: 'phone_already_joined' };
    }
    return this.attachPhone(session, now);
  }

  phoneDisconnected(session: PairingSession, now = Date.now()): void {
    if (session.ended || !session.phoneConnected) return;
    session.phoneConnected = false;
    session.controllerStage = 'lost';
    session.sequence = -1;
    session.resumeExpiresAt = now + PairingSessionService.phoneResumeLifetimeMs;
  }

  markPhoneActivity(session: PairingSession, now = Date.now()): void {
    session.lastPhoneActivityAt = now;
  }

  markGameActivity(session: PairingSession, now = Date.now()): void {
    session.lastGameActivityAt = now;
  }

  acceptInputRate(session: PairingSession, now = Date.now()): boolean {
    if (now - session.inputRateWindowStartedAt >= 1000) {
      session.inputRateWindowStartedAt = now;
      session.inputRateCount = 0;
    }
    session.inputRateCount++;
    return session.inputRateCount <= 60;
  }

  end(session: PairingSession): void {
    if (session.ended) return;
    session.ended = true;
    session.resumeToken = null;
    session.resumeExpiresAt = null;
    this.sessions.delete(session.id);
  }

  expired(session: PairingSession, now = Date.now()): boolean {
    if (session.ended) return true;
    if (!session.phoneConnected && session.resumeExpiresAt !== null) {
      return now > session.resumeExpiresAt;
    }
    return !session.phoneConnected && now >= session.pairingExpiresAt;
  }

  values(): IterableIterator<PairingSession> {
    return this.sessions.values();
  }

  private attachPhone(session: PairingSession, now: number): PairingResult {
    const credential = this.token();
    session.resumeToken = credential;
    session.resumeExpiresAt = null;
    session.generation++;
    session.sequence = -1;
    session.inputRateWindowStartedAt = now;
    session.inputRateCount = 0;
    session.phoneConnected = true;
    session.controllerStage = 'checking';
    session.lastPhoneActivityAt = now;
    return { ok: true, session, credential };
  }

  private token(): string {
    return randomBytes(24).toString('base64url');
  }
}
