# Apex RC Flutter client

The Flutter client keeps the five-screen racing demo and adds registration, login, role-aware entry, and an isolated product/category catalog. User accounts can view catalog data. Admin accounts can create, edit with `PUT`, and delete catalog records; the API enforces these permissions.

## Run with the local NestJS API

Start MongoDB and the API first by following [`../server/README.md`](../server/README.md). The Nest server listens on port `3000` by default.

For Flutter Web, use the exact default CORS origin and port:

```bash
cd client
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=LM_STUDIO_BASE_URL=http://192.168.101.139:1234/v1 \
  --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
```

`API_BASE_URL` is required at build/run time. For another Web origin or port, add its exact origin to the comma-separated `CORS_ORIGINS` setting in the server's local `.env`, then restart the API. Do not add a trailing API path to `API_BASE_URL`.

## Web Racing prototype

Milestone 1 can run without the API or MongoDB. Start the standalone two-player
keyboard prototype from `client/`:

```bash
flutter pub get
flutter run -d chrome -t lib/main_racing.dart \
  --web-hostname localhost --web-port 5174
```

Player 1 (red) uses `W A S D` and reserves `Q` for the horn input. Player 2
(blue) uses the arrow keys and reserves `M` for the horn input. Horn input is
available to the game logic, but the prototype does not play horn audio. Keep
the game focused while driving. Use **Bắt đầu đua**, **Tạm dừng**, **Reset xe**,
or `Esc` to pause. The existing authenticated app also has a **Chơi thử Web
Racing** button on its race tab.

Build the standalone Web entrypoint with:

```bash
flutter build web -t lib/main_racing.dart
```

## Apex RC AI assistant

The floating chat assistant calls the LM Studio OpenAI-compatible endpoint directly. Set `LM_STUDIO_BASE_URL` at build/run time to the address of the computer running LM Studio. The local Web command above uses `http://192.168.101.139:1234/v1`. The model defaults to `google/gemma-4-e2b` and can be changed with `LM_STUDIO_MODEL`.

For the setup in this demo, start the model in LM Studio, keep port `1234`, enable **Serve on Local Network**, and enable **Enable CORS** for Flutter Web. Restart the LM Studio server after changing its settings. The Flutter Web origin above is `http://localhost:5173`; if the browser Console reports a CORS error, verify that CORS is enabled in LM Studio. The app does not route AI requests through NestJS.

Run the Web demo against the local LM Studio host:

```bash
cd client
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=LM_STUDIO_BASE_URL=http://192.168.101.139:1234/v1 \
  --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
```

The Mac running Chrome and the LM Studio host must be able to reach each other on the local network; allow inbound TCP port `1234` in the host firewall. Check that `http://192.168.101.139:1234/v1/models` is reachable from the Mac before testing chat. If the page is served over HTTPS, browsers may block its HTTP AI request; use HTTPS for the AI endpoint or a local HTTP development origin.

The conversation stays in memory while navigating the five tabs and is cleared when the racing session ends. The full transcript remains visible, while each request sends the system instruction plus the latest 20 user/assistant messages.

The chat composer can attach one JPEG or PNG per message. Images are checked, resized so the longest edge is at most 1280 pixels, and limited to 10 MiB before processing and 5 MiB after resizing. The image preview remains in the transcript. Its Base64 data is sent with that message (and when retrying it); later requests retain the text transcript without resending earlier image data. If the assistant needs to inspect an earlier image again, attach it to a new message.

To verify image chat, run the Web command above, attach a JPEG and ask what is shown, then repeat with a PNG. Also try sending a PNG with no typed text to check the default analysis prompt, and send a follow-up question to confirm the old image is not uploaded again. In the browser Network panel, the request to `/chat/completions` should contain an `image_url` data URL with `image/jpeg` or `image/png`. If the browser Console reports CORS, enable **Enable CORS** in LM Studio and restart its local server; no NestJS proxy is used.

Android and iOS builds also need `LM_STUDIO_BASE_URL` set to an address reachable from that device. Android permits the current HTTP address in debug builds only. iOS may require a local-network usage description and a narrowly scoped App Transport Security setting. Do not use a broad arbitrary-loads exception for this local HTTP demo; prefer HTTPS for release builds.

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
flutter test \
  --dart-define=LM_STUDIO_BASE_URL=http://127.0.0.1:1234/v1 \
  --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
flutter build web \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=LM_STUDIO_BASE_URL=http://192.168.101.139:1234/v1 \
  --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
```
