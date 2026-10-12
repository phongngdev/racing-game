import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';

@Schema({ collection: 'auth_rate_limits' })
export class RateLimitBucket {
  @Prop({ type: String, required: true, unique: true })
  key!: string;

  @Prop({ type: Number, required: true, default: 0 })
  count!: number;

  @Prop({ type: Date, required: true })
  expiresAt!: Date;
}

export const RateLimitBucketSchema =
  SchemaFactory.createForClass(RateLimitBucket);
RateLimitBucketSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
