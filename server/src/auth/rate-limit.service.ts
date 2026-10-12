import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { RateLimitBucket } from './rate-limit.schema.js';

@Injectable()
export class RateLimitService {
  constructor(
    @InjectModel(RateLimitBucket.name)
    private readonly buckets: Model<RateLimitBucket>,
  ) {}

  async consume(
    key: string,
    limit: number,
    windowMs: number,
    now = new Date(),
  ): Promise<void> {
    const window = Math.floor(now.getTime() / windowMs);
    const bucketKey = `${key}:${window}`;
    const expiresAt = new Date((window + 1) * windowMs + 86_400_000);
    let bucket;
    try {
      bucket = await this.buckets
        .findOneAndUpdate(
          { key: bucketKey },
          { $inc: { count: 1 }, $setOnInsert: { expiresAt } },
          { upsert: true, returnDocument: 'after' },
        )
        .exec();
    } catch (error) {
      if (!this.isDuplicateKeyError(error)) throw error;
      bucket = await this.buckets
        .findOneAndUpdate(
          { key: bucketKey },
          { $inc: { count: 1 } },
          { returnDocument: 'after' },
        )
        .exec();
    }
    if (!bucket || bucket.count > limit) {
      throw new HttpException(
        'Too many requests. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private isDuplicateKeyError(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 11000
    );
  }
}
