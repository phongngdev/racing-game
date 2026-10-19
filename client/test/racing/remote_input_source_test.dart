import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/input/remote_input_source.dart';
import 'package:racing_client/racing/input/selectable_input_source.dart';

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
      ),
      isTrue,
    );
    expect(remote.inputFor(PlayerId.red).throttle, 1);
    now = const Duration(milliseconds: 301).inMicroseconds;
    expect(remote.hasFreshInput, isFalse);
    expect(remote.inputFor(PlayerId.red).throttle, 0);
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
    );
    expect(remote.readyToStart, isTrue);
    remote.lockUntilNeutral();
    remote.accept(
      sequence: 1,
      generation: 2,
      steering: 0.4,
      throttle: 1,
      brake: 0,
    );
    expect(remote.inputFor(PlayerId.red).throttle, 0);
    expect(remote.readyToStart, isFalse);
    remote.accept(
      sequence: 2,
      generation: 2,
      steering: 0.4,
      throttle: 0,
      brake: 0,
    );
    expect(remote.readyToStart, isTrue);
    expect(remote.inputFor(PlayerId.red).steering, 0.4);
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
    expect(selected.inputFor(PlayerId.blue).throttle, 0);
    keyboard.handleKey(LogicalKeyboardKey.arrowUp, true);
    expect(selected.inputFor(PlayerId.blue).throttle, 1);
    selected.select(RacingInputMode.keyboard);
    expect(selected.inputFor(PlayerId.red).throttle, 0);
    keyboard.handleKey(LogicalKeyboardKey.keyW, false);
    expect(selected.inputFor(PlayerId.red).throttle, 0);
  });
}
