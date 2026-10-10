# Racing Game API

NestJS backend for the Racing Game project. Milestone A connects the API to local MongoDB and exposes a database health check and Swagger documentation.

## Requirements

- Node.js and pnpm
- MongoDB running locally on `127.0.0.1:27017`

## Run locally

```bash
cp .env.example .env
pnpm install
pnpm start:dev
```

The default database URI is `mongodb://127.0.0.1:27017/racing_game`; the server listens on port `3000`. Set `MONGODB_URI` and `PORT` in `.env` to use different local values. Do not commit `.env`.

## Verify

- `GET http://localhost:3000/health` pings MongoDB and returns `200` when connected or `503` when unavailable.
- `http://localhost:3000/api/docs` opens Swagger UI.
- `http://localhost:3000/api/docs-json` serves the OpenAPI document.

```bash
pnpm build
pnpm lint
pnpm test
pnpm test:e2e
```
