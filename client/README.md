# Apex RC Flutter client

The Flutter client keeps the five-screen racing demo and adds registration, login, role-aware entry, and an isolated product/category catalog. User accounts can view catalog data. Admin accounts can create, edit with `PUT`, and delete catalog records; the API enforces these permissions.

## Run with the local NestJS API

Start MongoDB and the API first by following [`../server/README.md`](../server/README.md). The Nest server listens on port `3000` by default.

For Flutter Web, use the exact default CORS origin and port:

```bash
cd client
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

`API_BASE_URL` is required at build/run time. For another Web origin or port, add its exact origin to the comma-separated `CORS_ORIGINS` setting in the server's local `.env`, then restart the API. Do not add a trailing API path to `API_BASE_URL`.

For a physical Android device, connect the computer and phone to the same network, allow inbound connections to port `3000`, and use the computer's LAN address (for example `http://192.168.1.20:3000`):

```bash
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=http://<computer-lan-ip>:3000
```

Android emulator users can normally use `http://10.0.2.2:3000`. Android's cleartext HTTP allowance is limited to debug builds; use HTTPS for any non-development deployment. The API address is not a secret. Never put the server's MongoDB URI or JWT signing secret in Flutter.

## Accounts and sessions

Registering in the client always calls the public User registration endpoint. Create an Admin locally using the explicitly invoked `seed:admin` procedure in [`../server/README.md`](../server/README.md#create-a-development-admin); sign in again after seeding if the app already has a User session. Startup checks the token expiry locally and then verifies the token and role with `GET /auth/me`. If the API is temporarily unavailable, the client keeps the token and offers retry or logout. Logging out clears the stored token and in-memory session.

`shared_preferences` is used to persist the access token for this local demo. It is not intended as hardened secure storage for production secrets.

## Checks

```bash
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:3000
```
