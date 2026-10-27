import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { AuthModule } from '../auth/auth.module.js';
import { RaceHistory, RaceHistorySchema } from './race-history.schema.js';
import { RaceHistoriesController } from './race-histories.controller.js';
import { RaceHistoriesService } from './race-histories.service.js';

@Module({
  imports: [
    AuthModule,
    MongooseModule.forFeature([
      { name: RaceHistory.name, schema: RaceHistorySchema },
    ]),
  ],
  controllers: [RaceHistoriesController],
  providers: [RaceHistoriesService],
})
export class RaceHistoriesModule {}
