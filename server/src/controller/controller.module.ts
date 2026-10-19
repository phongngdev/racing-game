import { Module } from '@nestjs/common';
import { ControllerGateway } from './controller.gateway.js';

@Module({ providers: [ControllerGateway] })
export class ControllerModule {}
