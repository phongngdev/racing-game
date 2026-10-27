import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export enum RaceHistoryMode {
  Lap = 'lap',
  Sprint = 'sprint',
}

export enum RaceHistoryEndReason {
  Completed = 'completed',
  Deadline = 'deadline',
}

export enum RaceHistorySlot {
  P1 = 'p1',
  P2 = 'p2',
}

export enum RaceHistoryPlayerStatus {
  Finished = 'finished',
  Dnf = 'dnf',
}

@Schema({ _id: false })
export class RaceHistoryPlayer {
  @Prop({ type: String, required: true, enum: Object.values(RaceHistorySlot) })
  slot!: RaceHistorySlot;

  @Prop({ type: String, required: true, enum: ['red', 'blue'] })
  vehicle!: 'red' | 'blue';

  @Prop({ type: String, required: true, enum: ['phone', 'keyboard'] })
  source!: 'phone' | 'keyboard';

  @Prop({
    type: String,
    required: true,
    enum: Object.values(RaceHistoryPlayerStatus),
  })
  status!: RaceHistoryPlayerStatus;

  @Prop({ type: Number, default: null, min: 0 })
  finishTime!: number | null;

  @Prop({ type: Number, default: null, min: 1 })
  lapCount!: number | null;

  @Prop({ type: Number, default: null, min: 0 })
  completedLaps!: number | null;

  @Prop({ type: [Number], default: [] })
  lapTimes!: number[];

  @Prop({ type: Number, default: null, min: 0 })
  completedCheckpoints!: number | null;

  @Prop({ type: Number, default: null, min: 0 })
  totalCheckpoints!: number | null;
}

export const RaceHistoryPlayerSchema =
  SchemaFactory.createForClass(RaceHistoryPlayer);

@Schema({ collection: 'race_histories', versionKey: false })
export class RaceHistory {
  @Prop({ type: String, required: true })
  ownerUserId!: string;

  @Prop({ type: String, required: true, match: /^[0-9a-f]{32}$/ })
  raceId!: string;

  @Prop({ type: String, required: true, maxlength: 80 })
  roomId!: string;

  @Prop({ type: String, required: true, enum: Object.values(RaceHistoryMode) })
  mode!: RaceHistoryMode;

  @Prop({ type: String, required: true, maxlength: 120 })
  trackId!: string;

  @Prop({ type: String, default: null, maxlength: 120 })
  trackSeed!: string | null;

  @Prop({ type: Number, default: null, min: 1 })
  generatorVersion!: number | null;

  @Prop({ type: Date, required: true })
  startedAt!: Date;

  @Prop({ type: Date, required: true })
  endedAt!: Date;

  @Prop({ type: Number, required: true, min: 0 })
  durationMs!: number;

  @Prop({
    type: String,
    required: true,
    enum: Object.values(RaceHistoryEndReason),
  })
  endReason!: RaceHistoryEndReason;

  @Prop({ type: Boolean, required: true })
  isDraw!: boolean;

  @Prop({
    type: String,
    default: null,
    enum: [...Object.values(RaceHistorySlot), null],
  })
  winnerSlot!: RaceHistorySlot | null;

  @Prop({ type: [RaceHistoryPlayerSchema], required: true })
  players!: RaceHistoryPlayer[];
}

export type RaceHistoryDocument = HydratedDocument<RaceHistory>;
export const RaceHistorySchema = SchemaFactory.createForClass(RaceHistory);

RaceHistorySchema.index(
  { ownerUserId: 1, raceId: 1 },
  { unique: true, name: 'owner_race_unique' },
);
RaceHistorySchema.index(
  { ownerUserId: 1, endedAt: -1, _id: -1 },
  { name: 'owner_recent_first' },
);
