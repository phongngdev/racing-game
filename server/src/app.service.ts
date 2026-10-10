import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { InjectConnection } from '@nestjs/mongoose';
import type { Connection } from 'mongoose';

@Injectable()
export class AppService {
  constructor(@InjectConnection() private readonly connection: Connection) {}

  getHello(): string {
    return 'Hello World!';
  }

  async checkDatabase(): Promise<{ status: 'ok'; database: 'connected' }> {
    try {
      if (!this.connection.db) {
        throw new Error('MongoDB connection is not ready.');
      }
      await this.connection.db.admin().ping();
      return { status: 'ok', database: 'connected' };
    } catch {
      throw new ServiceUnavailableException({
        status: 'error',
        database: 'unavailable',
      });
    }
  }
}
