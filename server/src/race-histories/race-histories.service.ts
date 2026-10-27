import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { isObjectIdOrHexString, Model, Types } from 'mongoose';
import { PublicUser } from '../users/public-user.dto.js';
import {
  CreateRaceHistoryDto,
  RaceHistoryDto,
  RaceHistoryListDto,
} from './race-history.dto.js';
import {
  RaceHistory,
  RaceHistoryEndReason,
  RaceHistoryMode,
  RaceHistoryPlayerStatus,
  RaceHistorySlot,
} from './race-history.schema.js';

@Injectable()
export class RaceHistoriesService {
  constructor(
    @InjectModel(RaceHistory.name)
    private readonly histories: Model<RaceHistory>,
  ) {}

  async create(
    owner: PublicUser,
    input: CreateRaceHistoryDto,
  ): Promise<{ history: RaceHistoryDto; duplicate: boolean }> {
    this.validateResult(input);
    // Explicitly wait for the collection's unique index, including when Mongo
    // auto-indexing is disabled in production.
    await this.histories.init();
    const document = {
      raceId: input.raceId,
      roomId: input.roomId,
      mode: input.mode,
      trackId: input.trackId,
      trackSeed: input.trackSeed ?? null,
      generatorVersion: input.generatorVersion ?? null,
      durationMs: input.durationMs,
      endReason: input.endReason,
      isDraw: input.isDraw,
      winnerSlot: input.winnerSlot ?? null,
      ownerUserId: owner.id,
      startedAt: new Date(input.startedAt),
      endedAt: new Date(input.endedAt),
      players: input.players.map((player) => ({
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
    };

    try {
      const created = await this.histories.create(document);
      return { history: this.toDto(created), duplicate: false };
    } catch (error) {
      if (!this.isDuplicateKey(error)) throw error;
      const existing = await this.histories
        .findOne({ ownerUserId: owner.id, raceId: input.raceId })
        .exec();
      if (!existing) throw error;
      if (
        this.canonical(this.toDto(existing)) !==
        this.canonical({
          ...document,
          id: existing._id.toString(),
        })
      ) {
        throw new ConflictException(
          'raceId was already used for another result.',
        );
      }
      return { history: this.toDto(existing), duplicate: true };
    }
  }

  async list(
    owner: PublicUser,
    limit: number,
    cursor?: string,
  ): Promise<RaceHistoryListDto> {
    const pageSize = Math.min(Math.max(limit || 20, 1), 50);
    const filter: Record<string, unknown> = { ownerUserId: owner.id };
    if (cursor) {
      const decoded = this.decodeCursor(cursor);
      filter['$or'] = [
        { endedAt: { $lt: decoded.endedAt } },
        { endedAt: decoded.endedAt, _id: { $lt: decoded.id } },
      ];
    }
    const documents = await this.histories
      .find(filter)
      .sort({ endedAt: -1, _id: -1 })
      .limit(pageSize + 1)
      .exec();
    const hasMore = documents.length > pageSize;
    const page = documents.slice(0, pageSize);
    const last = page.at(-1);
    return {
      items: page.map((item) => this.toDto(item)),
      nextCursor: hasMore && last ? this.encodeCursor(last) : null,
    };
  }

  async findOne(owner: PublicUser, id: string): Promise<RaceHistoryDto> {
    if (!isObjectIdOrHexString(id)) {
      throw new BadRequestException('id must be a valid MongoDB ObjectId.');
    }
    const history = await this.histories
      .findOne({ _id: new Types.ObjectId(id), ownerUserId: owner.id })
      .exec();
    if (!history) throw new NotFoundException('Race history not found.');
    return this.toDto(history);
  }

  private validateResult(input: CreateRaceHistoryDto): void {
    if (!Object.values(RaceHistoryMode).includes(input.mode)) {
      throw new BadRequestException('Race mode is invalid.');
    }
    if (!Object.values(RaceHistoryEndReason).includes(input.endReason)) {
      throw new BadRequestException(
        'Only completed multiplayer races can be saved.',
      );
    }
    const startedAt = Date.parse(input.startedAt);
    const endedAt = Date.parse(input.endedAt);
    if (
      !Number.isFinite(startedAt) ||
      !Number.isFinite(endedAt) ||
      endedAt < startedAt
    ) {
      throw new BadRequestException('Race timestamps are invalid.');
    }
    if (input.durationMs > endedAt - startedAt + 5000) {
      throw new BadRequestException(
        'Race duration does not match its timestamps.',
      );
    }
    if (input.players[0]?.slot === input.players[1]?.slot) {
      throw new BadRequestException('A race must contain both player slots.');
    }
    const players = new Map(
      input.players.map((player) => [player.slot, player]),
    );
    if (!players.has(RaceHistorySlot.P1) || !players.has(RaceHistorySlot.P2)) {
      throw new BadRequestException('A race must contain P1 and P2.');
    }
    if (input.isDraw && input.winnerSlot != null) {
      throw new BadRequestException('A drawn race cannot have a winner.');
    }
    if (
      input.isDraw &&
      input.players.some(
        (player) => player.status !== RaceHistoryPlayerStatus.Finished,
      )
    ) {
      throw new BadRequestException('Both players must finish a drawn race.');
    }
    if (
      input.winnerSlot &&
      players.get(input.winnerSlot)?.status !== RaceHistoryPlayerStatus.Finished
    ) {
      throw new BadRequestException('The winner must have finished the race.');
    }
    if (
      input.endReason === RaceHistoryEndReason.Deadline &&
      !input.winnerSlot
    ) {
      throw new BadRequestException('A deadline result must have a winner.');
    }
    if (input.mode === RaceHistoryMode.Lap) {
      for (const player of input.players) {
        if (
          player.lapCount == null ||
          player.completedLaps == null ||
          player.completedCheckpoints != null ||
          player.totalCheckpoints != null ||
          player.completedLaps > player.lapCount ||
          player.lapTimes?.length !== player.completedLaps ||
          (player.status === RaceHistoryPlayerStatus.Finished &&
            player.finishTime == null) ||
          (player.status === RaceHistoryPlayerStatus.Dnf &&
            player.finishTime != null) ||
          player.lapTimes?.some((time) => !Number.isFinite(time) || time < 0)
        ) {
          throw new BadRequestException('Lap results are inconsistent.');
        }
      }
    } else {
      for (const player of input.players) {
        if (
          player.completedCheckpoints == null ||
          player.totalCheckpoints == null ||
          player.lapCount != null ||
          player.completedLaps != null ||
          player.lapTimes?.length ||
          player.completedCheckpoints > player.totalCheckpoints ||
          (player.status === RaceHistoryPlayerStatus.Finished &&
            player.finishTime == null) ||
          (player.status === RaceHistoryPlayerStatus.Dnf &&
            player.finishTime != null) ||
          (player.status === RaceHistoryPlayerStatus.Finished &&
            player.completedCheckpoints !== player.totalCheckpoints)
        ) {
          throw new BadRequestException('Sprint results are inconsistent.');
        }
      }
    }
  }

  private toDto(
    history: RaceHistory & { _id: Types.ObjectId },
  ): RaceHistoryDto {
    return {
      id: history._id.toString(),
      ownerUserId: history.ownerUserId,
      raceId: history.raceId,
      roomId: history.roomId,
      mode: history.mode,
      trackId: history.trackId,
      trackSeed: history.trackSeed,
      generatorVersion: history.generatorVersion,
      startedAt: history.startedAt.toISOString(),
      endedAt: history.endedAt.toISOString(),
      durationMs: history.durationMs,
      endReason: history.endReason,
      isDraw: history.isDraw,
      winnerSlot: history.winnerSlot,
      players: history.players.map((player) => ({
        slot: player.slot,
        vehicle: player.vehicle,
        source: player.source,
        status: player.status,
        finishTime: player.finishTime,
        lapCount: player.lapCount,
        completedLaps: player.completedLaps,
        lapTimes: player.lapTimes,
        completedCheckpoints: player.completedCheckpoints,
        totalCheckpoints: player.totalCheckpoints,
      })),
    };
  }

  private encodeCursor(history: RaceHistory & { _id: Types.ObjectId }): string {
    return Buffer.from(
      `${history.endedAt.toISOString()}|${history._id.toString()}`,
    ).toString('base64url');
  }

  private decodeCursor(cursor: string): { endedAt: Date; id: Types.ObjectId } {
    try {
      const decoded = Buffer.from(cursor, 'base64url').toString('utf8');
      const separator = decoded.lastIndexOf('|');
      const endedAt = new Date(decoded.slice(0, separator));
      const id = decoded.slice(separator + 1);
      if (
        separator < 0 ||
        !Number.isFinite(endedAt.getTime()) ||
        !isObjectIdOrHexString(id)
      ) {
        throw new Error('Invalid cursor');
      }
      return { endedAt, id: new Types.ObjectId(id) };
    } catch {
      throw new BadRequestException('cursor is invalid.');
    }
  }

  private isDuplicateKey(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 11000
    );
  }

  private canonical(value: unknown): string {
    const normalize = (item: unknown): unknown => {
      if (item instanceof Date) return item.toISOString();
      if (Array.isArray(item)) return item.map(normalize);
      if (typeof item !== 'object' || item === null) return item;
      return Object.fromEntries(
        Object.entries(item)
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([key, child]) => [key, normalize(child)]),
      );
    };
    return JSON.stringify(normalize(value));
  }
}
