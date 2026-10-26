import 'input/car_input.dart';
import 'race_progress.dart';
import 'race_session.dart';

/// Vietnamese labels for multiplayer race outcomes; race decisions stay in
/// [RaceSession] and its trackers.
abstract final class RaceResultsPresentation {
  static String title({required PlayerId? winner, required bool isDraw}) {
    if (isDraw) return 'HÒA';
    return switch (winner) {
      PlayerId.red => 'P1 CHIẾN THẮNG',
      PlayerId.blue => 'P2 CHIẾN THẮNG',
      null => 'KHÔNG CÓ NGƯỜI THẮNG',
    };
  }

  static String reason(
    RaceEndReason? reason, {
    required double finishWaitSeconds,
  }) => switch (reason) {
    RaceEndReason.completed => 'Cả hai người chơi đã hoàn thành cuộc đua.',
    RaceEndReason.deadline =>
      'Đã hết thời gian chờ ${_seconds(finishWaitSeconds)} sau khi người chơi đầu tiên về đích.',
    RaceEndReason.hostEnded => 'Chủ phòng đã kết thúc cuộc đua sớm.',
    RaceEndReason.roomClosed => 'Phòng đã đóng hoặc mất kết nối với máy chủ.',
    null => 'Cuộc đua đã kết thúc.',
  };

  static String playerStatus(
    RacePlayerStatus status, {
    double? finishTime,
    required String Function(double seconds) formatDuration,
  }) => switch (status) {
    RacePlayerStatus.finished =>
      finishTime == null
          ? 'VỀ ĐÍCH'
          : 'VỀ ĐÍCH · ${formatDuration(finishTime)}',
    RacePlayerStatus.dnf => 'DNF · Không hoàn thành',
    RacePlayerStatus.racing => 'ĐANG ĐUA',
  };

  static String _seconds(double value) {
    final rounded = value.roundToDouble();
    return value == rounded ? '${rounded.toInt()} giây' : '$value giây';
  }
}
