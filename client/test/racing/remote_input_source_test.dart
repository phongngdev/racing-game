import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/input/remote_input_source.dart';
import 'package:racing_client/racing/input/selectable_input_source.dart';
import 'package:racing_client/racing/input/multiplayer_input_source.dart';

void main() {
  test('accepts only fresh, ordered samples from the current generation', () {
    var now = 0;
    final remote = RemoteInputSource(clockMicros: () => now);
    remote.setConnected(true, generation: 7);
    expect(
      remote.accept(
        sequence: 1,
        generation: 7,
        steering: 0,
        throttle: 0,
        brake: 0,
        reverse: 0,
      ),
      isTrue,
    );
    expect(remote.readyToStart, isTrue);
    expect(
      remote.accept(
        sequence: 1,
        generation: 7,
        steering: 1,
        throttle: 1,
        brake: 0,
        reverse: 0,
      ),
      isFalse,
    );
    expect(
      remote.accept(
        sequence: 2,
        generation: 6,
        steering: 0,
        throttle: 1,
        brake: 0,
        reverse: 0,
      ),
      isFalse,
    );
    expect(
      remote.accept(
        sequence: 2,
        generation: 7,
        steering: double.nan,
        throttle: 1,
        brake: 0,
        reverse: 0,
      ),
      isFalse,
    );

    expect(
      remote.accept(
        sequence: 2,
        generation: 7,
        steering: -0.5,
        throttle: 1,
        brake: 0,
        reverse: 0,
      ),
      isTrue,
    );
    expect(remote.inputFor(PlayerId.red).throttle, 1);
    expect(remote.inputFor(PlayerId.red).emergencyStop, isFalse);
    now = const Duration(milliseconds: 301).inMicroseconds;
    expect(remote.hasFreshInput, isFalse);
    expect(remote.inputFor(PlayerId.red).throttle, 0);
    expect(remote.inputFor(PlayerId.red).emergencyStop, isTrue);
    expect(remote.readyToStart, isFalse);
  });

  test('requires a new released-pedal sample after lockout', () {
    var now = 0;
    final remote = RemoteInputSource(clockMicros: () => now);
    remote.setConnected(true, generation: 2);
    remote.accept(
      sequence: 0,
      generation: 2,
      steering: 0,
      throttle: 0,
      brake: 0,
      reverse: 0,
    );
    expect(remote.readyToStart, isTrue);
    remote.lockUntilNeutral();
    expect(remote.inputFor(PlayerId.red).emergencyStop, isTrue);
    remote.accept(
      sequence: 1,
      generation: 2,
      steering: 0.4,
      throttle: 1,
      brake: 0,
      reverse: 0,
    );
    expect(remote.inputFor(PlayerId.red).throttle, 0);
    expect(remote.readyToStart, isFalse);
    remote.accept(
      sequence: 2,
      generation: 2,
      steering: 0.4,
      throttle: 0,
      brake: 0,
      reverse: 0,
    );
    expect(remote.readyToStart, isTrue);
    expect(remote.inputFor(PlayerId.red).steering, 0.4);
    expect(remote.inputFor(PlayerId.red).emergencyStop, isFalse);
  });

  test('routes P2 input and locks only that car until a neutral sample after timeout', () {
    var now = 0;
    final remote = RemoteInputSource(
      clockMicros: () => now,
      player: PlayerId.blue,
      requireNeutralAfterTimeout: true,
    );
    remote.setConnected(true, generation: 4);
    remote.accept(
      sequence: 0,
      generation: 4,
      steering: 0,
      throttle: 0,
      brake: 0,
    );
    remote.accept(
      sequence: 1,
      generation: 4,
      steering: 0.2,
      throttle: 1,
      brake: 0,
    );
    expect(remote.inputFor(PlayerId.blue).throttle, 1);
    expect(remote.inputFor(PlayerId.red).throttle, 0);

    now = const Duration(milliseconds: 301).inMicroseconds;
    expect(remote.inputFor(PlayerId.blue).throttle, 0);
    expect(
      remote.accept(
        sequence: 2,
        generation: 4,
        steering: 0.2,
        throttle: 1,
        brake: 0,
      ),
      isTrue,
    );
    expect(remote.inputFor(PlayerId.blue).throttle, 0);
    expect(remote.readyToStart, isFalse);
    expect(
      remote.accept(
        sequence: 3,
        generation: 4,
        steering: 0,
        throttle: 0,
        brake: 0,
      ),
      isTrue,
    );
    expect(remote.readyToStart, isTrue);
    expect(remote.inputFor(PlayerId.blue).throttle, 0);
  });

  test('routes Phone and Keyboard independently by player', () {
    var now = 0;
    final redPhone = RemoteInputSource(
      clockMicros: () => now,
      player: PlayerId.red,
      requireNeutralAfterTimeout: true,
    )..setConnected(true, generation: 1);
    redPhone.accept(
      sequence: 0,
      generation: 1,
      steering: 0,
      throttle: 0,
      brake: 0,
    );
    final bluePhone = RemoteInputSource(
      clockMicros: () => now,
      player: PlayerId.blue,
      requireNeutralAfterTimeout: true,
    )..setConnected(true, generation: 1);
    bluePhone.accept(
      sequence: 0,
      generation: 1,
      steering: 0,
      throttle: 0,
      brake: 0,
    );
    final keyboard = KeyboardInputSource();
    final router = MultiplayerInputSource(
      keyboard: keyboard,
      phoneInputFor: (player) => player == PlayerId.red ? redPhone : bluePhone,
    );

    keyboard.handleKey(LogicalKeyboardKey.arrowUp, true);
    expect(router.inputFor(PlayerId.red).throttle, 0);
    expect(router.inputFor(PlayerId.blue).throttle, 1);

    router.setPhoneSelected(PlayerId.blue, true);
    bluePhone.accept(
      sequence: 1,
      generation: 1,
      steering: 0,
      throttle: 1,
      brake: 0,
    );
    expect(router.inputFor(PlayerId.blue).throttle, 0);
    bluePhone.accept(
      sequence: 2,
      generation: 1,
      steering: 0,
      throttle: 0,
      brake: 0,
    );
    expect(router.inputFor(PlayerId.blue).throttle, 0);
  });

  test('keeps reverse input out of neutral readiness until it is released', () {
    final remote = RemoteInputSource()..setConnected(true, generation: 3);
    remote.accept(
      sequence: 0,
      generation: 3,
      steering: 0,
      throttle: 0,
      reverse: 0,
      brake: 0,
    );
    expect(remote.readyToStart, isTrue);
    remote.accept(
      sequence: 1,
      generation: 3,
      steering: 0,
      throttle: 0,
      reverse: 1,
      brake: 0,
    );
    expect(remote.readyToStart, isFalse);
    expect(remote.inputFor(PlayerId.red).reverse, 1);
    remote.accept(
      sequence: 2,
      generation: 3,
      steering: 0,
      throttle: 0,
      reverse: 0,
      brake: 0,
    );
    expect(remote.readyToStart, isTrue);
  });

  test('keeps the blue keyboard and switches only the red car', () {
    final keyboard = KeyboardInputSource();
    final remote = RemoteInputSource();
    final selected = SelectableInputSource(keyboard: keyboard, remote: remote);
    keyboard.handleKey(LogicalKeyboardKey.keyW, true);
    keyboard.handleKey(LogicalKeyboardKey.arrowUp, true);
    expect(selected.inputFor(PlayerId.red).throttle, 1);
    selected.select(RacingInputMode.phone);
    expect(selected.inputFor(PlayerId.red).throttle, 0);
    expect(selected.inputFor(PlayerId.red).emergencyStop, isTrue);
    expect(selected.inputFor(PlayerId.blue).throttle, 0);
    keyboard.handleKey(LogicalKeyboardKey.arrowUp, true);
    expect(selected.inputFor(PlayerId.blue).throttle, 1);
    selected.select(RacingInputMode.keyboard);
    expect(selected.inputFor(PlayerId.red).throttle, 0);
    keyboard.handleKey(LogicalKeyboardKey.keyW, false);
    expect(selected.inputFor(PlayerId.red).throttle, 0);
  });
}
