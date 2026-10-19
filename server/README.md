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

For Google Sign-In, set `GOOGLE_WEB_CLIENT_ID` to the public Web OAuth client ID. Android and iOS request ID tokens for this server audience; the Android OAuth client must be registered in Google Cloud with package `com.phongngdev.racinggame` and the SHA-1 fingerprints of the signing certificates. iOS uses the iOS OAuth client and the same bundle ID. Add the exact Web origins used by the app (local development uses `http://localhost:5173`) to the Web OAuth client's Authorized JavaScript origins. Client IDs are public identifiers; do not put OAuth client secrets in the app.

Password reset requires `RESET_OTP_PEPPER`, a random value of at least 32 characters, plus Gmail SMTP settings (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`). Set `SMTP_FROM` to the sender address if it differs from `SMTP_USER`. Keep the App Password in the ignored local `.env`. Reset codes expire after five minutes; MongoDB enforces five guesses per code, three requests per email and ten requests per IP in each 15-minute window, and thirty verification attempts per IP in each window. Forgot-password returns the same response for existing and unknown accounts. A successful reset changes the Argon2id password and invalidates previously issued JWTs.

For Flutter Web development, the server allows `http://localhost:5173` and `http://127.0.0.1:5173` by default. Set `CORS_ORIGINS` to a comma-separated list of exact browser origins in `.env` if the client runs elsewhere, then restart NestJS. CORS is a browser policy; API authorization is still enforced by JWT and role guards.

The Web Racing prototype also uses the NestJS WebSocket relay at
`ws://<computer-lan-ip>:3000/controller`. Nest listens on all network
interfaces so a phone on the same LAN can reach it. Browser WebSocket origins
are checked separately from HTTP CORS; set `CONTROLLER_ALLOWED_ORIGINS` to the
exact game page origins if they differ from the defaults
(`http://localhost:5174,http://127.0.0.1:5174`). Android connects without a
browser Origin header. Keep the relay on a trusted development LAN; it has no
account pairing or authentication in this MVP.

The relay accepts one `game` client and one `phone` client. Run the game on the
PC, then run `main_controller.dart` on the Xiaomi using the PC's LAN IP. Valid
phone input is relayed in memory and is not stored in MongoDB. If the phone
stops sending heartbeats, the relay drops it after four seconds; the PC game
pauses after 300 ms without a valid input sample. A reconnect never starts the
race automatically.

The phone sends normalized `steering`, `throttle`, and `reverse` samples. The
relay accepts the legacy `brake` field for older clients. The running game can
send a `collision` event for a new impact involving the red car; the relay
forwards it only to the phone in the matching connection generation and limits
feedback to one event per 250 ms.

## Authentication API

- `POST /auth/register` accepts `{ "username", "email", "password" }` and creates a `User` account.
- `POST /auth/login` accepts `{ "username", "password" }` and returns an access token and public user details.
- `POST /auth/google` accepts `{ "idToken" }`; if the verified email belongs to a local account, retry with `{ "idToken", "linkPassword" }` to link it.
- `POST /auth/forgot-password` accepts `{ "email" }` and returns a generic accepted response.
- `POST /auth/reset-password` accepts `{ "email", "otp", "newPassword" }`; the OTP is single-use and expires after five minutes.
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

E2e tests use the separate `racing_game_test` database on local MongoDB and clear only its `users`, `products`, `categories`, and `auth_rate_limits` collections. Do not point the test configuration at the development database.

```bash
pnpm build
pnpm lint
pnpm test
pnpm test:e2e
```
