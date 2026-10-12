import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { getModelToken } from '@nestjs/mongoose';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { App } from 'supertest/types.js';
import { AppModule } from './../src/app.module.js';
import { setupHttp } from './../src/http-setup.js';
import { User, UserRole } from './../src/users/user.schema.js';
import { UsersService } from './../src/users/users.service.js';
import { EmailService } from './../src/auth/email.service.js';
import { RateLimitBucket } from './../src/auth/rate-limit.schema.js';

describe('AppController (e2e)', () => {
  let app: INestApplication<App>;
  let sentCodes: string[];

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    setupHttp(app);
    await app.init();
    await app.get(getModelToken(User.name)).init();
    await app.get(getModelToken(RateLimitBucket.name)).init();
    await app.get(getModelToken(User.name)).deleteMany({}).exec();
    await app.get(getModelToken(RateLimitBucket.name)).deleteMany({}).exec();
    sentCodes = [];
    vi.spyOn(app.get(EmailService), 'sendPasswordResetCode').mockImplementation(
      async (_email, code) => {
        sentCodes.push(code);
      },
    );
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

  it('allows the configured local Flutter Web origin and preflights CRUD methods', async () => {
    await request(app.getHttpServer())
      .get('/health')
      .set('Origin', 'http://localhost:5173')
      .expect(200)
      .expect('Access-Control-Allow-Origin', 'http://localhost:5173');

    await request(app.getHttpServer())
      .options('/products')
      .set('Origin', 'http://localhost:5173')
      .set('Access-Control-Request-Method', 'PUT')
      .set('Access-Control-Request-Headers', 'authorization,content-type')
      .expect(204)
      .expect('Access-Control-Allow-Origin', 'http://localhost:5173')
      .expect(({ headers }) => {
        expect(headers['access-control-allow-methods']).toContain('PUT');
        expect(headers['access-control-allow-headers']).toContain(
          'Authorization',
        );
      });
  });

  it('does not allow an unconfigured Web origin', async () => {
    await request(app.getHttpServer())
      .get('/health')
      .set('Origin', 'https://untrusted.example')
      .expect(200)
      .expect(({ headers }) => {
        expect(headers['access-control-allow-origin']).toBeUndefined();
      });
  });

  it('registers a normalized User and never exposes the password hash', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username: ' Racer_01 ',
        email: ' Racer@Example.com ',
        password: 'correct-horse-123',
      })
      .expect(201);

    expect(response.body).toMatchObject({
      username: 'racer_01',
      email: 'racer@example.com',
      role: UserRole.User,
    });
    expect(response.body).not.toHaveProperty('passwordHash');
  });

  it('rejects duplicate usernames and emails with 409', async () => {
    await registerRacer();

    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username: ' Racer_01 ',
        email: 'another@example.com',
        password: 'another-pass-123',
      })
      .expect(409);

    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username: 'another_racer',
        email: ' RACER@EXAMPLE.COM ',
        password: 'another-pass-123',
      })
      .expect(409);
  });

  it('allows only one of two concurrent registrations for the same account', async () => {
    const payload = {
      username: 'concurrent_racer',
      email: 'concurrent@example.com',
      password: 'concurrent-pass-123',
    };
    const results = await Promise.all(
      Array.from({ length: 2 }, () =>
        request(app.getHttpServer()).post('/auth/register').send(payload),
      ),
    );

    expect(
      results
        .map((result) => result.status)
        .sort((left, right) => left - right),
    ).toEqual([201, 409]);
  });

  it('rejects attempts to register as Admin and unknown fields', async () => {
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username: 'intruder',
        email: 'intruder@example.com',
        password: 'correct-horse-123',
        role: UserRole.Admin,
      })
      .expect(400);

    const count = await app
      .get(getModelToken(User.name))
      .countDocuments({ username: 'intruder' })
      .exec();
    expect(count).toBe(0);
  });

  it('logs in and returns the database role from /auth/me', async () => {
    await registerRacer();
    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'racer_01', password: 'correct-horse-123' })
      .expect(200);

    expect(login.body.accessToken).toEqual(expect.any(String));
    expect(login.body.user.role).toBe(UserRole.User);
    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${login.body.accessToken}`)
      .expect(200)
      .expect(({ body }) => {
        expect(body).toMatchObject({
          username: 'racer_01',
          email: 'racer@example.com',
          role: UserRole.User,
        });
        expect(body).not.toHaveProperty('passwordHash');
      });
  });

  it('rejects an incorrect password with 401', async () => {
    await registerRacer();
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'racer_01', password: 'wrong-password-123' })
      .expect(401);
  });

  it('rejects missing, malformed, tampered and expired tokens', async () => {
    await registerRacer();
    const jwt = app.get(JwtService);
    const validToken = await jwt.signAsync({ sub: '000000000000000000000001' });
    const expiredToken = await jwt.signAsync(
      { sub: '000000000000000000000001' },
      { expiresIn: '-1s' },
    );

    await request(app.getHttpServer()).get('/auth/me').expect(401);
    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', 'Bearer not-a-jwt')
      .expect(401);
    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${validToken.slice(0, -1)}x`)
      .expect(401);
    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${expiredToken}`)
      .expect(401);
  });

  it('can create and authenticate an Admin through the internal seed service', async () => {
    const users = app.get(UsersService);
    await users.createAdmin({
      username: 'test_admin',
      email: 'admin@example.com',
      password: 'test-admin-pass-123',
    });

    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'test_admin', password: 'test-admin-pass-123' })
      .expect(200);

    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${login.body.accessToken}`)
      .expect(200)
      .expect(({ body }) => expect(body.role).toBe(UserRole.Admin));
  });

  it('documents bearer auth for /auth/me in Swagger', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/docs-json')
      .expect(200);

    expect(response.body.paths['/auth/me'].get.security).toEqual([
      { bearer: [] },
    ]);
    expect(response.body.paths['/auth/google'].post).toBeDefined();
    expect(response.body.paths['/auth/forgot-password'].post).toBeDefined();
    expect(response.body.paths['/auth/reset-password'].post).toBeDefined();
  });

  it('resets a password once, rejects brute-force attempts, and revokes old JWTs', async () => {
    await registerRacer();
    const oldSession = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'racer_01', password: 'correct-horse-123' })
      .expect(200);

    const existing = await request(app.getHttpServer())
      .post('/auth/forgot-password')
      .send({ email: 'racer@example.com' })
      .expect(202);
    const unknown = await request(app.getHttpServer())
      .post('/auth/forgot-password')
      .send({ email: 'unknown@example.com' })
      .expect(202);
    expect(existing.body).toEqual(unknown.body);
    expect(sentCodes).toHaveLength(2);

    await app
      .get(getModelToken(User.name))
      .updateOne(
        { email: 'racer@example.com' },
        { $set: { resetOtpExpiresAt: new Date(Date.now() - 1000) } },
      )
      .exec();
    await request(app.getHttpServer())
      .post('/auth/reset-password')
      .send({
        email: 'racer@example.com',
        otp: sentCodes[0],
        newPassword: 'new-racing-pass-123',
      })
      .expect(400);

    await request(app.getHttpServer())
      .post('/auth/forgot-password')
      .send({ email: 'racer@example.com' })
      .expect(202);
    const expiredCode = sentCodes[2];
    const wrongCode = expiredCode === '000000' ? '000001' : '000000';
    for (let attempt = 0; attempt < 5; attempt++) {
      await request(app.getHttpServer())
        .post('/auth/reset-password')
        .send({
          email: 'racer@example.com',
          otp: wrongCode,
          newPassword: 'new-racing-pass-123',
        })
        .expect(400);
    }
    await request(app.getHttpServer())
      .post('/auth/reset-password')
      .send({
        email: 'racer@example.com',
        otp: expiredCode,
        newPassword: 'new-racing-pass-123',
      })
      .expect(400);

    await request(app.getHttpServer())
      .post('/auth/forgot-password')
      .send({ email: 'racer@example.com' })
      .expect(202);
    const validCode = sentCodes[3];
    await request(app.getHttpServer())
      .post('/auth/reset-password')
      .send({
        email: 'racer@example.com',
        otp: validCode,
        newPassword: 'new-racing-pass-123',
      })
      .expect(200);
    await request(app.getHttpServer())
      .post('/auth/reset-password')
      .send({
        email: 'racer@example.com',
        otp: validCode,
        newPassword: 'another-racing-pass-123',
      })
      .expect(400);
    await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${oldSession.body.accessToken}`)
      .expect(401);
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'racer_01', password: 'correct-horse-123' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ username: 'racer_01', password: 'new-racing-pass-123' })
      .expect(200);
  });

  afterEach(async () => {
    await app.get(getModelToken(User.name)).deleteMany({}).exec();
    await app.get(getModelToken(RateLimitBucket.name)).deleteMany({}).exec();
    await app.close();
  });

  async function registerRacer(): Promise<void> {
    await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        username: 'racer_01',
        email: 'racer@example.com',
        password: 'correct-horse-123',
      })
      .expect(201);
  }
});
