import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Types } from 'mongoose';
import { PublicUser } from '../users/public-user.dto.js';
import { CreateRaceHistoryDto } from './race-history.dto.js';
import {
  RaceHistory,
  RaceHistoryEndReason,
  RaceHistoryMode,
  RaceHistoryPlayerStatus,
  RaceHistorySlot,
  RaceHistorySchema,
} from './race-history.schema.js';
import { RaceHistoriesService } from './race-histories.service.js';

const owner: PublicUser = {
  id: '0123456789abcdef01234567',
  username: 'racer_01',
  email: 'racer@example.com',
  role: 'User' as PublicUser['role'],
};

const input = () =>
  ({
    raceId: '0123456789abcdef0123456789abcdef',
    roomId: 'f00542a1-3f6d-49b3-b746-00216f5d5c58',
    mode: RaceHistoryMode.Lap,
    trackId: 'apex-loop',
    startedAt: '2026-10-27T10:00:00.000Z',
    endedAt: '2026-10-27T10:00:20.000Z',
    durationMs: 19000,
    endReason: RaceHistoryEndReason.Completed,
    isDraw: false,
    winnerSlot: RaceHistorySlot.P1,
    players: [
      {
        slot: RaceHistorySlot.P1,
        vehicle: 'red',
        source: 'phone',
        status: RaceHistoryPlayerStatus.Finished,
        finishTime: 18,
        lapCount: 3,
        completedLaps: 3,
        lapTimes: [6, 6, 6],
      },
      {
        slot: RaceHistorySlot.P2,
        vehicle: 'blue',
        source: 'keyboard',
        status: RaceHistoryPlayerStatus.Finished,
        finishTime: 19,
        lapCount: 3,
        completedLaps: 3,
        lapTimes: [6, 6, 7],
      },
    ],
  }) satisfies CreateRaceHistoryDto;

function documentFor(
  value: Record<string, unknown>,
  id = '66c1a10d6b9a5e9a6a1c0123',
) {
  return {
    ...value,
    _id: new Types.ObjectId(id),
  };
}

function storedHistory(endedAt: string, objectId: string) {
  const value = input();
  return documentFor(
    {
      ...value,
      ownerUserId: owner.id,
      startedAt: new Date(value.startedAt),
      endedAt: new Date(endedAt),
      trackSeed: null,
      generatorVersion: null,
      players: value.players.map((player) => ({
        ...player,
        finishTime: player.finishTime ?? null,
        lapCount: player.lapCount ?? null,
        completedLaps: player.completedLaps ?? null,
        lapTimes: player.lapTimes ?? [],
        completedCheckpoints: null,
        totalCheckpoints: null,
      })),
    },
    objectId,
  );
}

describe('RaceHistoriesService', () => {
  it('uses only the race_histories collection and adds owner scoped indexes', () => {
    expect(RaceHistorySchema.get('collection')).toBe('race_histories');
    expect(RaceHistorySchema.indexes()).toEqual(
      expect.arrayContaining([
        [
          { ownerUserId: 1, raceId: 1 },
          expect.objectContaining({ unique: true }),
        ],
        [{ ownerUserId: 1, endedAt: -1, _id: -1 }, expect.any(Object)],
      ]),
    );
  });

  it('stores the JWT user as owner and creates one document', async () => {
    const create = vi.fn(async (value: Record<string, unknown>) =>
      documentFor(value),
    );
    const init = vi.fn().mockResolvedValue(undefined);
    const service = new RaceHistoriesService({
      create,
      init,
    } as unknown as import('mongoose').Model<RaceHistory>);

    const result = await service.create(owner, input());

    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        ownerUserId: owner.id,
        raceId: input().raceId,
      }),
    );
    expect(init).toHaveBeenCalledOnce();
    expect(result.duplicate).toBe(false);
    expect(result.history.ownerUserId).toBe(owner.id);
  });

  it('accepts an identical retry and rejects reuse of a race id for different data', async () => {
    const value = input();
    const stored = documentFor({
      ...value,
      ownerUserId: owner.id,
      startedAt: new Date(value.startedAt),
      endedAt: new Date(value.endedAt),
      trackSeed: null,
      generatorVersion: null,
      winnerSlot: value.winnerSlot,
      players: value.players.map((player) => ({
        slot: player.slot,
        vehicle: player.vehicle,
        source: player.source,
        status: player.status,
        finishTime: player.finishTime ?? null,
        lapCount: player.lapCount ?? null,
        completedLaps: player.completedLaps ?? null,
        lapTimes: player.lapTimes ?? [],
        completedCheckpoints: player.completedCheckpoints ?? null,
        totalCheckpoints: player.totalCheckpoints ?? null,
      })),
    });
    const duplicateError = Object.assign(new Error('duplicate key'), {
      code: 11000,
    });
    const create = vi.fn().mockRejectedValue(duplicateError);
    const init = vi.fn().mockResolvedValue(undefined);
    const findOne = vi
      .fn()
      .mockReturnValue({ exec: vi.fn().mockResolvedValue(stored) });
    const service = new RaceHistoriesService({
      create,
      init,
      findOne,
    } as unknown as import('mongoose').Model<RaceHistory>);

    const retry = await service.create(owner, value);
    expect(retry.duplicate).toBe(true);

    await expect(
      service.create(owner, { ...value, trackId: 'another-track' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('lists only the current account in newest first order with a cursor', async () => {
    const latest = storedHistory(
      '2026-10-27T10:00:20.000Z',
      '66c1a10d6b9a5e9a6a1c0124',
    );
    const older = storedHistory(
      '2026-10-27T09:59:20.000Z',
      '66c1a10d6b9a5e9a6a1c0123',
    );
    const exec = vi.fn().mockResolvedValue([latest, older]);
    const limit = vi.fn().mockReturnValue({ exec });
    const sort = vi.fn().mockReturnValue({ limit });
    const find = vi.fn().mockReturnValue({ sort });
    const service = new RaceHistoriesService({
      find,
    } as unknown as import('mongoose').Model<RaceHistory>);

    const page = await service.list(owner, 1);

    expect(find).toHaveBeenCalledWith({ ownerUserId: owner.id });
    expect(sort).toHaveBeenCalledWith({ endedAt: -1, _id: -1 });
    expect(limit).toHaveBeenCalledWith(2);
    expect(page.items.map((item) => item.id)).toEqual([latest._id.toString()]);
    expect(page.nextCursor).toBeTruthy();
  });

  it('validates result mode and refuses incomplete or spoofed winner snapshots', async () => {
    const create = vi.fn();
    const service = new RaceHistoriesService({
      create,
    } as unknown as import('mongoose').Model<RaceHistory>);

    await expect(
      service.create(owner, {
        ...input(),
        endReason: 'roomClosed' as RaceHistoryEndReason,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.create(owner, { ...input(), players: [input().players[0]!] }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.create(owner, {
        ...input(),
        winnerSlot: RaceHistorySlot.P2,
        players: [
          input().players[0]!,
          {
            ...input().players[1]!,
            status: RaceHistoryPlayerStatus.Dnf,
            finishTime: null,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(create).not.toHaveBeenCalled();
  });

  it('scopes detail reads to the current account', async () => {
    const findOne = vi
      .fn()
      .mockReturnValue({ exec: vi.fn().mockResolvedValue(null) });
    const service = new RaceHistoriesService({
      findOne,
    } as unknown as import('mongoose').Model<RaceHistory>);

    await expect(
      service.findOne(owner, '66c1a10d6b9a5e9a6a1c0123'),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(findOne).toHaveBeenCalledWith({
      _id: new Types.ObjectId('66c1a10d6b9a5e9a6a1c0123'),
      ownerUserId: owner.id,
    });
  });
});
