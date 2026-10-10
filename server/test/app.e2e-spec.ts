import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types.js';
import { AppModule } from './../src/app.module.js';
import { setupSwagger } from './../src/swagger.js';

describe('AppController (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    setupSwagger(app);
    await app.init();
  });

  it('/ (GET)', () => {
    return request(app.getHttpServer())
      .get('/')
      .expect(200)
      .expect('Hello World!');
  });

  it('/health (GET) verifies MongoDB connectivity', () => {
    return request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok', database: 'connected' });
  });

  it('/api/docs (GET) serves Swagger UI', () => {
    return request(app.getHttpServer()).get('/api/docs').expect(200);
  });

  it('/api/docs-json (GET) describes the health endpoint', () => {
    return request(app.getHttpServer())
      .get('/api/docs-json')
      .expect(200)
      .expect(({ body }) => {
        expect(body.paths['/health']).toBeDefined();
      });
  });

  afterEach(async () => {
    await app.close();
  });
});
