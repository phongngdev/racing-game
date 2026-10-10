import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { AppService } from './app.service.js';

@ApiTags('health')
@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Get('health')
  @ApiOperation({ summary: 'Check API and MongoDB availability' })
  @ApiResponse({ status: 200, description: 'MongoDB is connected.' })
  @ApiResponse({ status: 503, description: 'MongoDB is unavailable.' })
  checkHealth() {
    return this.appService.checkDatabase();
  }
}
