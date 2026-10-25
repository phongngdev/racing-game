import { Module } from '@nestjs/common';
import { ControllerGateway } from './controller.gateway.js';
import { PairingSessionService } from './pairing-session.service.js';
import { MultiplayerRoomService } from './multiplayer-room.service.js';

@Module({
  providers: [ControllerGateway, PairingSessionService, MultiplayerRoomService],
})
export class ControllerModule {}
