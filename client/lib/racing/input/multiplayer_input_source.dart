import 'car_input.dart';
import 'remote_input_source.dart';

/// Routes each car to its current keyboard or phone source.
class MultiplayerInputSource implements InputSource {
  MultiplayerInputSource({required this.keyboard, required this.phoneInputFor});

  final KeyboardInputSource keyboard;
  final RemoteInputSource Function(PlayerId player) phoneInputFor;
  final Map<PlayerId, bool> _phoneSlots = {
    PlayerId.red: true,
    PlayerId.blue: false,
  };

  bool isPhoneSelected(PlayerId player) => _phoneSlots[player] ?? false;

  void setPhoneSelected(PlayerId player, bool selected) {
    if (isPhoneSelected(player) == selected) return;
    _phoneSlots[player] = selected;
    keyboard.clear();
    phoneInputFor(player).lockUntilNeutral();
  }

  void clear() {
    keyboard.clear();
    phoneInputFor(PlayerId.red).lockUntilNeutral();
    phoneInputFor(PlayerId.blue).lockUntilNeutral();
  }

  @override
  CarInput inputFor(PlayerId player) => isPhoneSelected(player)
      ? phoneInputFor(player).inputFor(player)
      : keyboard.inputFor(player);
}
