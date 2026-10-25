import { MultiplayerRoomService } from './multiplayer-room.service.js';

describe('MultiplayerRoomService', () => {
  it('creates two fixed slots with phone and keyboard defaults and private invites', () => {
    const service = new MultiplayerRoomService();
    const room = service.create(100);

    expect(room.slots.p1).toMatchObject({ id: 'p1', player: 'red', source: 'phone' });
    expect(room.slots.p2).toMatchObject({
      id: 'p2',
      player: 'blue',
      source: 'keyboard',
      pairingToken: null,
    });
    expect(room.slots.p1.pairingToken).toHaveLength(32);
    expect(service.snapshot(room)).not.toHaveProperty('slots.0.pairingToken');
  });

  it('claims one slot once and resumes only its disconnected owner', () => {
    const service = new MultiplayerRoomService();
    const room = service.create(100);
    const token = room.slots.p1.pairingToken;
    const joined = service.join(room.id, 'p1', token, 101);
    expect(joined.ok).toBe(true);
    if (!joined.ok || !joined.slot || !joined.credential) return;

    expect(service.join(room.id, 'p1', token, 102)).toEqual({
      ok: false,
      code: 'slot_in_use',
    });
    expect(service.join(room.id, 'p2', token, 102)).toEqual({
      ok: false,
      code: 'slot_not_phone',
    });
    service.disconnected(joined.slot, 200);
    expect(service.resume(room.id, 'p1', joined.credential, 201).ok).toBe(true);
  });

  it('separates temporary disconnect, explicit leave, expiry, and host reset', () => {
    const service = new MultiplayerRoomService();
    const room = service.create(100);
    const joined = service.join(room.id, 'p1', room.slots.p1.pairingToken, 101);
    if (!joined.ok || !joined.slot || !joined.credential) return;

    service.disconnected(joined.slot, 200);
    expect(service.expiredResumeSlots(room, 30_199)).toEqual([]);
    expect(service.expiredResumeSlots(room, 30_201)).toContain(joined.slot);
    expect(joined.slot.resumeToken).toBeNull();
    expect(joined.slot.pairingToken).toBeTruthy();

    const second = service.join(room.id, 'p1', joined.slot.pairingToken, 30_202);
    if (!second.ok || !second.slot) return;
    service.leave(second.slot);
    expect(second.slot.connected).toBe(false);
    expect(second.slot.resumeToken).toBeNull();
    expect(second.slot.pairingToken).toBeTruthy();
    expect(service.resume(room.id, 'p1', second.credential, 30_203)).toEqual({
      ok: false,
      code: 'resume_expired',
    });

    service.configure(room, second.slot, 'keyboard', 30_203);
    expect(second.slot.source).toBe('keyboard');
    expect(second.slot.pairingToken).toBeNull();
    service.configure(room, second.slot, 'phone', 30_204);
    expect(second.slot.pairingToken).toBeTruthy();
  });
});
