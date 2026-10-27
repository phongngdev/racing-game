import { ValidationPipe } from '@nestjs/common';
import { Types } from 'mongoose';
import type { Model } from 'mongoose';
import { CreateRaceHistoryDto } from './race-history.dto.js';
import { RaceHistoriesService } from './race-histories.service.js';
import { RaceHistory } from './race-history.schema.js';
import { UserRole } from '../users/user.schema.js';

function sprintPayload(seed = 'Sprint-nw3hm5') {
  return {
    raceId: '0123456789abcdef0123456789abcdef',
    roomId: '5f835b17-3f6d-49b3-b746-00216f5d5c58',
    mode: 'sprint',
    trackId: `sprint-v1:${seed}`,
    trackSeed: seed,
    generatorVersion: 1,
    startedAt: '2026-10-27T02:22:00.000Z',
    endedAt: '2026-10-27T02:22:48.433Z',
    durationMs: 48433,
    endReason: 'completed',
    isDraw: false,
    winnerSlot: 'p2',
    players: ['p1', 'p2'].map((slot) => ({
      slot,
      vehicle: slot === 'p1' ? 'red' : 'blue',
      source: slot === 'p1' ? 'phone' : 'keyboard',
      status: 'finished',
      finishTime: slot === 'p1' ? 48.433 : 46.89,
      lapCount: null,
      completedLaps: null,
      lapTimes: [],
      completedCheckpoints: 8,
      totalCheckpoints: 8,
    })),
  };
}

const pipe = new ValidationPipe({
  transform: true,
  whitelist: true,
  forbidNonWhitelisted: true,
});

function validate(payload: unknown): Promise<CreateRaceHistoryDto> {
  return pipe.transform(payload, {
    type: 'body',
    metatype: CreateRaceHistoryDto,
  }) as Promise<CreateRaceHistoryDto>;
}

describe('Race history HTTP payload validation', () => {
  it('accepts the generated Sprint ID and passes the real result to persistence', async () => {
    const payload = await validate(sprintPayload());
    const create = vi.fn(async (document: Record<string, unknown>) => ({
      ...document,
      _id: new Types.ObjectId(),
    }));
    const service = new RaceHistoriesService({
      init: vi.fn().mockResolvedValue(undefined),
      create,
    } as unknown as Model<RaceHistory>);

    const result = await service.create(
      {
        id: '0123456789abcdef01234567',
        username: 'racer_01',
        email: 'racer@example.com',
        role: UserRole.User,
      },
      payload,
    );

    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        trackId: 'sprint-v1:Sprint-nw3hm5',
        trackSeed: 'Sprint-nw3hm5',
        winnerSlot: 'p2',
      }),
    );
    expect(result.history.players).toHaveLength(2);
    expect(result.duplicate).toBe(false);
  });

  it('accepts spaces and Unicode allowed by the existing seed generator', async () => {
    await expect(
      validate(sprintPayload('Đường đua demo 01')),
    ).resolves.toBeDefined();
  });

  it.each(['', 'x'.repeat(121)])(
    'rejects an empty or oversized track ID',
    async (trackId) => {
      await expect(validate({ ...sprintPayload(), trackId })).rejects.toThrow();
    },
  );

  it('rejects a client supplied owner ID', async () => {
    await expect(
      validate({
        ...sprintPayload(),
        ownerUserId: 'someone-else',
      }),
    ).rejects.toThrow();
  });
});
