# Apex RC Flutter client

The main Flutter app has Trang chủ, Chơi, and Cài đặt destinations, plus registration, login, role-aware entry, and an isolated product/category catalog. Practice supports keyboard controls or a paired Android phone controller. The standalone Web Racing prototype remains available through `main_racing.dart`, and the standalone manual phone controller remains available through `main_controller.dart`. User accounts can view catalog data. Admin accounts can create, edit with `PUT`, and delete catalog records; the API enforces these permissions.

## Run with the local NestJS API

Start MongoDB and the API first by following [`../server/README.md`](../server/README.md). The Nest server listens on port `3000` by default.

For Flutter Web, use the exact default CORS origin and port. Set the controller URL to the LAN address of the NestJS relay when using Practice with a phone:

```bash
cd client
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=CONTROLLER_WS_URL=ws://192.168.1.20:3000/controller \
  --dart-define=LM_STUDIO_BASE_URL=http://192.168.101.139:1234/v1 \
  --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
```

`API_BASE_URL` is required at build/run time. For another Web origin or port, add its exact origin to the comma-separated `CORS_ORIGINS` setting in the server's local `.env`, then restart the API. Do not add a trailing API path to `API_BASE_URL`.

## Web Racing prototype

Keyboard mode can run without the API or MongoDB. Start the standalone racing
game from `client/`; start NestJS and MongoDB as described below to use the
phone relay:

```bash
flutter pub get
flutter run -d chrome -t lib/main_racing.dart \
  --web-hostname localhost --web-port 5174 \
  --dart-define=CONTROLLER_WS_URL=ws://127.0.0.1:3000/controller
```

Player 1 (red) uses `W` to accelerate, `S` to reverse, and `A/D` to steer,
reserving `Q` for the horn input. Player 2 (blue) uses the arrow keys with the
same directions and reserves `M` for the horn input. Horn input is
available to the game logic, but the prototype does not play horn audio. Keep
the game focused while driving. Use **Bắt đầu đua**, **Tạm dừng**, **Reset xe**,
or `Esc` to pause. In the authenticated app, open **Chơi → Practice** to use
WASD for the red car and the arrow keys for the blue car. Press **Bắt đầu đua**
inside the game to start the simulation. This keyboard Practice path does not
create a phone relay connection; the phone controller remains available in the
standalone prototype.

### Practice phone pairing

Start NestJS using [`../server/README.md`](../server/README.md). On the PC,
start the main Flutter Web app with `CONTROLLER_WS_URL` set to the relay's
reachable LAN address. In **Chơi → Practice**, choose **Điện thoại**. If the
URL is not configured, enter it in the setup screen. The address must use the
NestJS machine's LAN IP and `/controller` path; `localhost` and `127.0.0.1`
cannot be used in a QR code.

On the Xiaomi, install/run the Android app from `main.dart` (not the standalone
manual controller entry point):

```bash
flutter devices
flutter run -d <xiaomi-device-id>
```

Tap **Quét QR** on the Android entry screen; no Google sign-in is needed for the
controller. Allow camera access, scan the PC code, hold the phone in landscape,
keep it straight, and press **Cân tâm** when the sensor is ready. The phone
shows GA/LÙI, steering and collision vibration controls. The PC enables
**Bắt đầu Practice** only after the phone has calibrated, sent a fresh sensor
sample, and released both pedals. Then press the in-game **Bắt đầu đua** button.

The QR token expires after five minutes and can only be claimed once. A phone
may resume with its private in-app credential for up to 30 seconds after a
detected disconnect; scanning the QR on another phone does not take over the
session. Leaving the game, switching to keyboard, or losing the PC relay ends
the session. A new session requires a new QR. If phone input becomes stale,
Practice pauses and does not resume automatically. Allow inbound TCP port 3000
through the relay host firewall and make sure Wi-Fi does not isolate devices.

For manual controller debugging, `main_controller.dart` still accepts a
WebSocket URL directly and uses the original v1 relay protocol. Android debug
builds already allow cleartext LAN WebSockets; release builds do not enable a
global cleartext exception.

Build the standalone Web entrypoint with:

```bash
flutter build web -t lib/main_racing.dart
```

For Phone mode in a built Web app, pass the relay address at build time:

```bash
flutter build web -t lib/main_racing.dart \
  --dart-define=CONTROLLER_WS_URL=ws://127.0.0.1:3000/controller
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

The conversation stays in memory while navigating the app and is cleared when the authenticated app shell ends. The full transcript remains visible, while each request sends the system instruction plus the latest 20 user/assistant messages.

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
