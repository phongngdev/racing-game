# Racing Game API

NestJS backend for the Racing Game project. The API connects to local MongoDB, exposes health and Swagger endpoints, supports JWT authentication, and provides protected product/category CRUD for the instructor demo.

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

## Products and categories demo

Every product and category endpoint requires `Authorization: Bearer <accessToken>`. Both User and Admin roles can list or view records. Only Admin can create, replace with `PUT`, or delete them. Product requests require a `name` and non-negative numeric `price`; `description` is optional and `categoryId` may be omitted or set to `null`.

Use Swagger at `http://localhost:3000/api/docs` to demonstrate the flow:

1. Create an Admin with the procedure in **Create a development Admin** below, then register a separate User through `POST /auth/register`.

2. Sign in as Admin using `POST /auth/login`, copy the returned `accessToken`, then choose **Authorize** in Swagger and enter the token. Create a category with `POST /categories`, then create a product with `POST /products` using that category's `id` as `categoryId`.
3. Demonstrate `GET /products`, `GET /categories`, `PUT /products/{id}`, `PUT /categories/{id}`, and the matching `DELETE` operations. Deleting a category retains its products and returns their `categoryId` as `null`.
4. Sign in as the separate User, authorize with that token, and demonstrate that both GET routes work while POST, PUT, and DELETE return `403`.

Category names are unique without regard to capitalization. A `PUT` replaces all editable fields: omitting `description` clears it; omitting `categoryId` removes the product's category. IDs must be MongoDB ObjectIds. Invalid input returns `400`, missing records return `404`, duplicate category names return `409`, and unauthenticated requests return `401`.

Deleting a category first unlinks its products and then removes the category. These are sequential MongoDB operations, not one transaction; concurrent writes during deletion are not atomic.

## Create a development Admin

Set `ADMIN_USERNAME`, `ADMIN_EMAIL`, and `ADMIN_PASSWORD` in your ignored local `.env`, then explicitly run:

```bash
NODE_ENV=development pnpm seed:admin
```

The command creates an Admin only in development and fails if the username or email is already in use. It never resets or promotes an existing account.

## Tests

E2e tests use the separate `racing_game_test` database on local MongoDB and clear only its `users`, `products`, and `categories` collections. Do not point the test configuration at the development database.

```bash
pnpm build
pnpm lint
pnpm test
pnpm test:e2e
```
