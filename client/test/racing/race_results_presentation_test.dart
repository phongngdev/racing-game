import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/racing/input/car_input.dart';
import 'package:racing_client/racing/race_progress.dart';
import 'package:racing_client/racing/race_results_presentation.dart';
import 'package:racing_client/racing/race_session.dart';

void main() {
  group('multiplayer Results presentation', () {
    test('winner and draw titles preserve race outcome mapping', () {
      expect(
        RaceResultsPresentation.title(winner: PlayerId.red, isDraw: false),
        'P1 CHIẾN THẮNG',
      );
      expect(
        RaceResultsPresentation.title(winner: PlayerId.blue, isDraw: false),
        'P2 CHIẾN THẮNG',
      );
      expect(RaceResultsPresentation.title(winner: null, isDraw: true), 'HÒA');
      expect(
        RaceResultsPresentation.title(winner: null, isDraw: false),
        'KHÔNG CÓ NGƯỜI THẮNG',
      );
    });

    test('every supported end reason has a distinct Vietnamese message', () {
      const wait = 60.0;
      expect(
        RaceResultsPresentation.reason(
          RaceEndReason.completed,
          finishWaitSeconds: wait,
        ),
        'Cả hai người chơi đã hoàn thành cuộc đua.',
      );
      expect(
        RaceResultsPresentation.reason(
          RaceEndReason.deadline,
          finishWaitSeconds: wait,
        ),
        'Đã hết thời gian chờ 60 giây sau khi người chơi đầu tiên về đích.',
      );
      expect(
        RaceResultsPresentation.reason(
          RaceEndReason.hostEnded,
          finishWaitSeconds: wait,
        ),
        'Chủ phòng đã kết thúc cuộc đua sớm.',
      );
      expect(
        RaceResultsPresentation.reason(
          RaceEndReason.roomClosed,
          finishWaitSeconds: wait,
        ),
        'Phòng đã đóng hoặc mất kết nối với máy chủ.',
      );
      expect(
        RaceResultsPresentation.reason(null, finishWaitSeconds: wait),
        'Cuộc đua đã kết thúc.',
      );
    });

    test('finish, DNF, and racing statuses remain distinct', () {
      String duration(double seconds) => '${seconds.toStringAsFixed(3)} giây';

      expect(
        RaceResultsPresentation.playerStatus(
          RacePlayerStatus.finished,
          finishTime: 12.5,
          formatDuration: duration,
        ),
        'VỀ ĐÍCH · 12.500 giây',
      );
      expect(
        RaceResultsPresentation.playerStatus(
          RacePlayerStatus.dnf,
          formatDuration: duration,
        ),
        'DNF · Không hoàn thành',
      );
      expect(
        RaceResultsPresentation.playerStatus(
          RacePlayerStatus.racing,
          formatDuration: duration,
        ),
        'ĐANG ĐUA',
      );
    });
  });
}
