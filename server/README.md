# Racing Game API

NestJS backend for the Racing Game project. The API connects to local MongoDB, exposes health and Swagger endpoints, and supports username based account registration and JWT authentication.

## Requirements

- Node.js and pnpm
- MongoDB running locally on `127.0.0.1:27017`

## Run locally

```bash
cp .env.example .env # only when .env does not already exist
pnpm install
pnpm start:dev
```

Set `JWT_SECRET` to a random value of at least 32 characters; `openssl rand -base64 48` generates one. `JWT_EXPIRES_IN` defaults to `1h`. Keep `.env` local and do not commit it. The default database URI is `mongodb://127.0.0.1:27017/racing_game`; the server listens on port `3000`.

## Authentication API

- `POST /auth/register` accepts `{ "username", "email", "password" }` and creates a `User` account.
- `POST /auth/login` accepts `{ "username", "password" }` and returns an access token and public user details.
- `GET /auth/me` requires `Authorization: Bearer <accessToken>` and returns the current public user and role.
- `GET http://localhost:3000/health` pings MongoDB and returns `200` when connected or `503` when unavailable.
- `http://localhost:3000/api/docs` opens Swagger UI.
- `http://localhost:3000/api/docs-json` serves the OpenAPI document.

## Create a development Admin

Set `ADMIN_USERNAME`, `ADMIN_EMAIL`, and `ADMIN_PASSWORD` in your ignored local `.env`, then explicitly run:

```bash
NODE_ENV=development pnpm seed:admin
```

The command creates an Admin only in development and fails if the username or email is already in use. It never resets or promotes an existing account.

## Tests

E2e tests use the separate `racing_game_test` database on local MongoDB and clear only its `users` collection.

```bash
pnpm build
pnpm lint
pnpm test
pnpm test:e2e
```
