# Milestone 5 — Sprint Race

Sprint lives alongside the existing three-lap race in the Multiplayer lobby.
It uses one simulation, one race session/clock, one Flame world, and two cameras.
The existing renderer is Flame 1.38.2 with Canvas drawing in components; no engine
or dependency was added.

## Implementation

- The fixed corridor is 3600 × 2200, 200 units wide, with eight ordered checkpoints.
  The distance from the side-by-side grid to the finish is 7000 world units.
- `TrackDefinition.corridor` compiles one cardinal centerline into road rectangles,
  closed collision walls, spawns, directed gates and route stations. It rejects
  diagonal/short segments, intersections, touching nonadjacent roads, and routes
  too close to the world boundary. A future generator can provide a centerline to
  this factory; no random generation or seed handling is implemented here.
- A common `RaceSession` owns the existing countdown, fixed-step clock, results,
  60-second deadline and reset flow. `LapRaceSession` remains a compatibility
  adapter; Sprint has its own tracker. Lap's backtrack rule is unchanged. Sprint
  rolls back to a checkpoint crossed backwards and requires recrossing it.
- Sprint progress projects only onto the current validated route interval. It
  can decrease while reversing and never grants checkpoints or a winner by itself.
- Two Flame cameras read the same world. Panes are left/right on wide layouts and
  top/bottom on narrower layouts. Each keeps a 480-unit short-axis view, smoothed
  follow, bounded velocity look-ahead and world clamping. A finished player's pane
  stays assigned to that player while the other camera continues independently.
- Track and car rendering reject geometry outside the current camera's viewport.
  Track geometry and paints are reused. The Sprint HUD refreshes at 10 Hz without
  changing the simulation rate. No spatial index was added.
- Source changes remain restricted to Lobby/Pause. Finished vehicles remain still
  and do not participate in car-to-car collisions. Restart and Rematch reset both
  vehicles and cameras; they do not recreate the WebSocket room.

## Files

Existing files updated:

- `lib/main.dart`
- `lib/pages/multiplayer_setup_page.dart`
- `lib/racing/apex_racing_game.dart`
- `lib/racing/multiplayer_race_page.dart`
- `lib/racing/simulation/race_simulation.dart`
- `lib/racing/lap/lap_race_track.dart`
- `lib/racing/lap/lap_player_tracker.dart`
- `lib/racing/lap/lap_race_rules.dart`
- `lib/racing/lap/lap_race_session.dart`
- `test/racing/lap_player_tracker_test.dart`
- `test/racing/lap_race_session_test.dart`
- `test/racing/lap_race_track_test.dart`
- `test/racing/multiplayer_room_session_test.dart`
- `test/racing/remote_input_source_test.dart`
- `test/widget_test.dart`

New files:

- `lib/racing/race_mode.dart`, `race_mode_selector.dart`, `race_progress.dart`,
  `race_rules.dart`, `race_session.dart`
- `lib/racing/tracks/track_definition.dart`, `track_geometry.dart`
- `lib/racing/sprint/sprint_player_tracker.dart`, `sprint_race_session.dart`,
  `sprint_camera.dart`, `sprint_track_component.dart`
- `test/racing/sprint_track_test.dart`, `sprint_player_tracker_test.dart`,
  `sprint_race_session_test.dart`, `sprint_camera_test.dart`,
  `multiplayer_sprint_page_test.dart`, `helpers/room_fixture.dart`
- This guide: `MILESTONE_5.md`

Several old regression fixtures were corrected when tests became runnable:
gate samples now match their gate order, QR room state includes its actual invite
expiry field, and phone samples send neutral after connecting. The countdown-loss
fixture now marks both availability and readiness false. The app navigation test
also stops expecting the obsolete Multiplayer "coming soon" badge. These adjustments do not
change production WebSocket/controller behavior.

## Windows: P1 Phone + P2 Keyboard

1. Start the existing API/relay and its configured services:

   ```powershell
   cd C:\racing-game\server
   npm run start:dev
   ```

2. Connect Android and map the relay/API port. Use the current ID from
   `adb devices` if the wireless device ID has changed:

   ```powershell
   adb -s adb-b14d54eb-etWopc._adb-tls-connect._tcp reverse tcp:3000 tcp:3000
   ```

3. Web terminal:

   ```powershell
   cd C:\racing-game\client
   flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=ALLOW_USB_RELAY=true --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=CONTROLLER_WS_URL=ws://127.0.0.1:3000/controller
   ```

4. Android terminal:

   ```powershell
   cd C:\racing-game\client
   flutter run -d adb-b14d54eb-etWopc._adb-tls-connect._tcp -t lib/main.dart --dart-define=ALLOW_USB_RELAY=true --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=CONTROLLER_WS_URL=ws://127.0.0.1:3000/controller
   ```

   Existing LM Studio defines may be kept. To use phone AI features with a loopback
   LM Studio address, also reverse port 1234; this is not required for racing.

5. Open **Chơi → Multiplayer**, create a room, leave P1 as Phone and P2 as Keyboard,
   scan P1 QR and calibrate/neutralize the phone. Select **Sprint Race** and enter
   the track. Start countdown; P2 drives with arrow keys.
6. Follow the centerline arrows and green checkpoint lines. Use Pause to Restart,
   reconnect/show QR or change Phone/Keyboard. Rematch appears only in Results and
   retains the selected mode and room. Return to Lobby to choose Lap instead.

For LAN Wi-Fi instead of ADB reverse, enter the reachable PC relay address in the
Lobby and use the reachable PC API address on Android. No IP is hardcoded by the
Sprint implementation.

## Validation and manual checks

Run from `client/`:

```powershell
flutter test --no-pub test/racing test/controller
flutter test --no-pub --dart-define=LM_STUDIO_BASE_URL=http://127.0.0.1:1234/v1 --dart-define=LM_STUDIO_MODEL=google/gemma-4-e2b
flutter test --no-pub test/racing/practice_page_test.dart test/controller/pairing_payload_test.dart test/racing/sprint_camera_test.dart --dart-define=CONTROLLER_WS_URL=ws://192.168.1.20:3000/controller --dart-define=ALLOW_USB_RELAY=true
dart analyze lib/racing lib/pages/multiplayer_setup_page.dart lib/main.dart test/racing
```

Recorded verification for this milestone:

- Full client suite with the LM Studio test defines: **117 passed, 1 skipped**.
  The skipped case requires a configured relay URL.
- Configured-relay Practice + USB QR + camera run above: **11 passed**, including
  the case skipped by the default relay configuration.
- Analyzer for changed production/test code: **no issues**.
- `flutter build web --debug --no-pub` with API/relay USB defines: **passed**;
  Flutter's Wasm dry run also succeeded. This is not a real-browser Wasm test.
- `git diff --check`: **passed**.

Tests cover road/wall coverage, turn clearance, ordered/reverse/finite gate
crossings, progress rollback, both players finishing (each can win and ties are
order-independent), DNF/Pause/Restart/Rematch, room closure, camera resize/follow,
one-clock behavior, HUD and mode changes preserving the room. Test-only drivers
also drive each spawn through the full route using actual physics and walls.
Existing Lap, Practice, input routing and controller tests remain regression gates.

The initial sandboxed Flutter invocation could not access the SDK cache lockfile.
Tests can run with normal SDK cache permissions; no SDK or system configuration
needs to be changed.

Actual Chrome FPS/frame time and physical Android/LAN reconnect behavior require
manual measurement. In Chrome DevTools Performance, record at least 30 seconds
with two cars moving through corners, then repeat with them far apart and after
one finishes. Record average FPS, long frames and frame-time distribution, with
the browser viewport and machine details. Flutter widget-test timing is synthetic
and is not a browser performance benchmark.
