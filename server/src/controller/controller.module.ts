import { Module } from '@nestjs/common';
import { ControllerGateway } from './controller.gateway.js';
import { PairingSessionService } from './pairing-session.service.js';

@Module({ providers: [ControllerGateway, PairingSessionService] })
export class ControllerModule {}
