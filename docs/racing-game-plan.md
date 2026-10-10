# Racing Game — Implementation Plan (Flutter + NestJS + MongoDB)

> Working document for Codex. Implement incrementally, inspect the existing repository before changing code, and preserve the existing Flutter UI.

## 1. Context and objective

Repository root: `racing-game/`. This is a Flutter racing-game project in which a phone is intended to act as a controller for the racing game. The Flutter UI was created earlier under `demo_ui` and is being moved/renamed to `client/`; backend lives under `server/` and uses NestJS. **Do not replace the game with a product-management app.**

The immediate assignment is to demonstrate the functionality described in `LTDD Tuan7 V2.docx` (week 7 mobile development exercise), using **NestJS + MongoDB/Mongoose** rather than the sample's ASP.NET Core + SQL Server. Technologies in the handout are examples; required behavior is the focus. Backend is locally developed on macOS with Homebrew MongoDB running at `mongodb://127.0.0.1:27017` and the `racing_game` database already created. A test document exists in `players`; it is **not** an authenticated application user.

The sample handout covers: register/login, JWT decoding, environment-based API URL, persistence of a session token, Admin/User roles and correct role-based navigation, product APIs; its final-page individual exercises add logout, correct role on cold start, list-products authorization, optional smart_auth, category relationships/CRUD, and unlinking products when deleting a category. Those requirements are for a **small learning/demo feature inside the racing-game project**, not a redesign of the game. If the instructor requires exact product/category demonstration, implement a simple isolated feature or demo screens without removing or overwriting racing-game UI.

## 2. Guardrails for Codex

1. Inspect the repository before coding: Flutter app structure, `pubspec.yaml`, existing navigation/BLoC, NestJS version and scripts, git status, existing `.env.example`/`.gitignore`, existing modules, and tests. Do not assume paths or code that are not present.
2. Preserve the Flutter UI/navigation, existing `IndexedStack`, existing state-management approach (BLoC if already used), and gameplay/controller code. Make focused, small changes.
3. NestJS is the only backend. MongoDB + `@nestjs/mongoose` / Mongoose is the persistence layer. No ASP.NET, SQL Server, Prisma, Redis, or unnecessary architecture/tools.
4. Prefer simple NestJS feature modules, DTO validation, dependency injection, and straightforward REST endpoints. Avoid premature abstractions or microservices.
5. Keep secrets out of git. Commit `.env.example` placeholders only. Never hardcode signing secrets in source. A Flutter web `.env` or `--dart-define` config is **not secret storage**; do not put DB credentials or JWT signing keys there.
6. Stop at the end of each milestone, summarize changes, show commands/tests/results and remaining gaps; ask before major unrelated refactors. If blocked, report the exact issue rather than silently changing tech stack.
7. Use the existing installed versions when compatible and pin sensible dependency ranges. Do not automatically upgrade pnpm, Flutter, Node, or the NestJS CLI.

## 3. Target repository layout (adapt to reality)

```text
racing-game/
├── client/                       # existing Flutter UI/game, preserve
│   ├── lib/
│   │   ├── config/              # API base URL config
│   │   ├── services/            # API client/auth service
│   │   └── ...                  # existing screens, BLoC, widgets etc.
│   └── pubspec.yaml
├── server/                       # NestJS app
│   ├── src/
│   │   ├── auth/                # signup/login/JWT
│   │   ├── users/               # MongoDB users + role
│   │   ├── products/            # assignment demo API
│   │   ├── categories/          # assignment demo API
│   │   └── ...                  # app.module.ts, main.ts etc.
│   └── .env.example
├── README.md
└── racing-game-plan.md
```

Use existing conventions rather than forcibly reorganizing every file. A root workspace tool is optional and not needed initially.

## 4. Minimum working API contract (proposed; finalize before connecting Flutter)

These endpoint names are a **proposed design**, not literal routes required by the handout. Keep them consistent and document the final contract.

| Method | Endpoint | Authentication | Behavior |
|---|---|---|---|
| POST | `/auth/register` | Public | Register `User` role only; validate username/email/password; hash password; reject duplicates; never accept client-controlled Admin role |
| POST | `/auth/login` | Public | Validate credentials; return signed access token and minimal current-user info, including role |
| GET | `/auth/me` | Bearer JWT | Return authoritative current user info/role |
| GET | `/products` | Bearer JWT | List products; apply explicit role rule agreed for the assignment |
| POST | `/products` | Admin | Create product with optional valid category |
| PATCH | `/products/:id` | Admin | Update product/category association |
| DELETE | `/products/:id` | Admin | Delete product |
| GET | `/categories` | Bearer JWT | List categories |
| POST | `/categories` | Admin | Create category |
| PATCH | `/categories/:id` | Admin | Update category |
| DELETE | `/categories/:id` | Admin | Delete category; set related product `categoryId` to `null`, do not delete products |

The handout calls for access control on the list-products endpoint but does **not** unambiguously specify which roles may list products. **Do not invent this as a handout requirement**: propose `Admin` and `User` as allowed, protected from anonymous access, and confirm with the user/instructor if a stricter rule is expected.

Optional helper: `GET /health` to verify API availability. Use standard HTTP responses (`201`, `200`, `400`, `401`, `403`, `404`, `409`) and consistently structured errors. Use `/api` prefix only if it makes integration clearer; update Flutter base URL accordingly.

## 5. Data model

**users**
- `username`: unique, trimmed
- `email`: unique, normalized
- `passwordHash`: never expose via responses
- `role`: `User` or `Admin`, default `User`
- timestamps

**categories**
- `name`: required, ideally unique
- optional description
- timestamps

**products** (assignment demonstration, not the racing-game domain)
- `name`: required
- `description`: optional
- `price`: nonnegative number, if product demo needs one
- `categoryId`: optional MongoDB ObjectId ref to category, `null` after category deletion
- timestamps

Use Mongoose schema validators and NestJS DTOs (`class-validator`, `class-transformer`); document uniqueness constraints and return clear duplicate/conflict errors. Use a nullable reference rather than cascading product deletion. For simple local demo, deleting a category should first `$set: { categoryId: null }` on dependent products, then remove the category (document that multi-step operation is not fully atomic without a transaction). Avoid requiring a MongoDB replica set solely for this assignment.

## 6. Auth/security rules

- Hash passwords using `argon2` or `bcrypt`; never store plaintext.
- Use `@nestjs/jwt` and Passport JWT guard (or an equivalent well-tested NestJS guard) with secret loaded via `@nestjs/config` and a configurable expiry, e.g. `1h`.
- JWT payload should contain an immutable user id (`sub`) and minimal claims. Fetch/validate current user and role on protected requests as needed; server enforces roles regardless of what Flutter displays.
- Public registration **must not** accept arbitrary `Admin` role. For grading, seed a development-only Admin via an explicitly invoked safe script/CLI using env-provided credentials, or use an authorized admin-only creation flow. Do not publish default admin passwords.
- Enable DTO validation with whitelist/forbid unknown properties where practical; guard protected endpoints; configure CORS for actual Flutter web local dev origin(s), not blanket `*` with credentials.
- For production, use HTTPS, proper secrets, DB auth, rate limiting/login protection, etc. Local MongoDB without authentication is acceptable **only for local-only development**.

## 7. Flutter integration requirements

Do **not** rebuild existing UI from the instructor's Facebook-style screenshots. Adapt existing screens or add minimal Login/Register/Admin/demo pages as needed.

- Use one centrally configured API base URL (`--dart-define` or a Flutter env package, if already used). For Flutter web running on same Mac, `http://127.0.0.1:3000` can work; for a **physical phone**, localhost means the phone itself, so use the Mac's reachable LAN IP or a properly hosted HTTPS API. Configure CORS for the frontend web origin, not the API origin.
- Implement shared HTTP client with JSON encoding, error handling, timeouts, and Bearer `Authorization` header on authenticated endpoints.
- Use `jwt_decoder` only to read display/session metadata and expiration; **decoding a JWT is not proof of validity**. The NestJS server validates signatures and authorization.
- Use `shared_preferences` as the handout demonstrates for local token persistence; note that this is not high-security storage, especially on web. Avoid logging or exposing tokens. Consider stronger storage for production mobile versions.
- On app start, read stored token, check expiry, then call `/auth/me` to verify it is accepted and obtain the actual role. If missing/expired/invalid, remove token and display Login.
- Navigate `Admin` to an Admin screen; `User` to existing main/game screen. The **same rule must apply after restarting the app**. Protect the admin route/widget, but treat UI navigation only as convenience; enforce access server-side.
- Logout removes persisted token, clears in-memory auth state, and navigates to Login (clearing protected navigation history).
- If BLoC is in use, place login/logout/bootstrap state in the existing pattern rather than duplicating ad-hoc state across screens.
- Use `mounted` checks after asynchronous operations before using `BuildContext`.
- Smart Auth is optional/bonus and platform dependent; verify actual supported features/plugins for the target platform before attempting. Prioritize required functionality first.

## 8. Milestones and acceptance checks

### Milestone A — Repository and connection (do first)
- Verify NestJS server exists and starts (`pnpm start:dev`). If the prior `nest new` failed, resolve scaffolding first; do not assume success.
- Install only required dependencies: Mongo integration + config + validation (later auth packages).
- Add `server/.env.example` with `MONGODB_URI=mongodb://127.0.0.1:27017/racing_game`, `JWT_SECRET=<set-locally>`, `JWT_EXPIRES_IN=1h`, `PORT=3000` (example values only). Add real `.env` to gitignore.
- Connect Mongoose in AppModule. Add small health check or verify app start + Mongo connection. Document commands.
- **Acceptance:** `pnpm start:dev` works; MongoDB connection succeeds; no secret committed.

### Milestone B — Users + authentication
- Add User schema, registration/login DTOs, service/controller, password hashing, JWT issue/verify and guards.
- Seed Admin only through a dev-only explicit mechanism.
- **Acceptance:** User registration works; duplicated user/email rejected; wrong password gives 401; JWT grants `/auth/me`; missing/invalid token rejected; public role escalation rejected; Admin and User can be tested separately.

### Milestone C — Products/categories + authorization
- Implement product/category schemas, CRUD and category unlink behavior. Use clear validation and 404s.
- Add guards and roles to endpoints; confirm exact product-list restriction.
- **Acceptance:** Admin can add/edit/delete categories; User cannot mutate Admin-only resources; deleting a category preserves related products and clears `categoryId`; product listing requires allowed authorization.

### Milestone D — Flutter integration
- Inspect current Flutter structure and reuse screens/state management.
- Add API configuration, client, auth service, login/register, token persistence, bootstrap and role-aware navigation, logout, minimal product/category demo UI where necessary.
- **Acceptance:** Register → login → correct screen; cold restart → same role screen; expired/invalid token → login; logout → login; User cannot access Admin functionality even by calling API manually.

### Milestone E — Demo readiness
- Add concise README with startup steps for Mongo, NestJS, Flutter web/phone, API environment configuration, and how to seed/test an Admin.
- Provide a short smoke-test script or curl/HTTP examples for registration, login, protected reads, admin CRUD, and deleting a category with retained products.
- Run available NestJS tests/lint and Flutter analyze/tests. Report real results and any skipped/unavailable test clearly.
- Keep racing-controller/game feature development **out of scope** for this week unless explicitly requested.

## 9. Assignment mapping (from the handout)

| Handout item | Implementation |
|---|---|
| Identity-based register/login | NestJS auth + Mongo `users` + password hashing |
| JWT decode, claims, expiry | NestJS signed JWT + Flutter decode for metadata + `/auth/me` verification |
| `flutter_dotenv` / API URL | Central Flutter API config (package or dart-define) |
| `shared_preferences` | Persist session token and restore conditionally |
| Admin/User authorization | Server-side JWT + roles guards, role-specific Flutter navigation |
| Homework 1 logout | Clear token + auth state |
| Homework 2 correct Admin login screen | Role-aware redirect after login |
| Homework 3 correct role after app restart | Validate stored token and fetch role on bootstrap |
| Homework 4 product-list authorization | Guard product listing; confirm role policy |
| Homework 5 `smart_auth` | Optional extra credit after required work |
| Homework 6 one category per product | Optional `categoryId` reference |
| Homework 7 Admin category CRUD | Guarded category create/update/delete |
| Homework 8 delete category, retain products | Unlink referencing products (`categoryId: null`) |

## 10. First instruction to Codex

> Inspect the current `racing-game` repo and report the existing Flutter/NestJS structure, scripts, dependencies, and git status. Then implement **Milestone A only**: local MongoDB/Mongoose connection, environment config, and a way to verify server startup. Do not modify or recreate the existing Flutter UI, do not start later milestones yet, and do not upgrade unrelated tooling. Run relevant checks and report all files changed, commands, results, and any blockers. Once Milestone A is accepted, we'll proceed to auth.
