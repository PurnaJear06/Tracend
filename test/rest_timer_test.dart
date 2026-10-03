import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';

class _RecordingAlerts implements RestAlertScheduler {
  final scheduled = <int>[];
  int cancels = 0;

  @override
  Future<bool> scheduleRestAlert(int seconds) async {
    scheduled.add(seconds);
    return true;
  }

  @override
  Future<void> cancelRestAlert() async => cancels++;
}

void main() {
  final start = DateTime.utc(2026, 10, 3, 9);

  group('RestTimer', () {
    test('counts down from its end time', () {
      final timer = RestTimer.start(90, now: start);

      expect(timer.remainingSeconds(start), 90);
      expect(
        timer.remainingSeconds(start.add(const Duration(milliseconds: 500))),
        90,
      );
      expect(timer.remainingSeconds(start.add(const Duration(seconds: 89))), 1);
      expect(timer.remainingSeconds(start.add(const Duration(seconds: 95))), 0);
      expect(timer.isExpired(start.add(const Duration(seconds: 90))), isTrue);
      expect(timer.progress(start.add(const Duration(seconds: 45))), 0.5);
    });

    test('+15 and -15 move the end and the ring length', () {
      final timer = RestTimer.start(90, now: start);

      final longer = timer.adjusted(RestTimer.step);
      expect(longer.endsAt, start.add(const Duration(seconds: 105)));
      expect(longer.totalSeconds, 105);

      final shorter = timer.adjusted(-RestTimer.step);
      expect(shorter.remainingSeconds(start), 75);
      expect(shorter.totalSeconds, 75);
    });

    test('survives the draft as JSON', () {
      final timer = RestTimer.start(120, now: start);
      final draft =
          jsonDecode(jsonEncode({RestTimer.draftKey: timer.toJson()})) as Map;
      final restored = RestTimer.fromJson(draft[RestTimer.draftKey]);

      expect(restored!.endsAt, timer.endsAt);
      expect(restored.totalSeconds, 120);
    });

    test('an unreadable stored timer is no timer', () {
      expect(RestTimer.fromJson(null), isNull);
      expect(RestTimer.fromJson('soon'), isNull);
      expect(
        RestTimer.fromJson({'ends_at': 'later', 'total_seconds': 90}),
        isNull,
      );
      expect(
        RestTimer.fromJson({
          'ends_at': start.toIso8601String(),
          'total_seconds': 0,
        }),
        isNull,
      );
    });
  });

  group('RestTimerController', () {
    late DateTime now;
    late _RecordingAlerts alerts;
    late RestTimerController controller;

    setUp(() {
      now = start;
      alerts = _RecordingAlerts();
      controller = RestTimerController(alerts: alerts, clock: () => now);
    });

    test('start schedules the alert for the full rest', () async {
      await controller.start(90);

      expect(controller.timer!.remainingSeconds(now), 90);
      expect(alerts.scheduled, [90]);
      expect(controller.toDraft(), controller.timer!.toJson());
    });

    test('a new start replaces the running rest', () async {
      await controller.start(90);
      now = now.add(const Duration(seconds: 20));
      await controller.start(60);

      expect(controller.timer!.remainingSeconds(now), 60);
      expect(alerts.scheduled, [90, 60]);
    });

    test('a zero rest starts nothing', () async {
      await controller.start(0);

      expect(controller.timer, isNull);
      expect(alerts.scheduled, isEmpty);
      expect(alerts.cancels, 1);
    });

    test('adjust reschedules for the time left', () async {
      await controller.start(90);
      now = now.add(const Duration(seconds: 40));

      await controller.adjust(RestTimer.step);
      expect(alerts.scheduled.last, 65);

      await controller.adjust(-RestTimer.step);
      expect(alerts.scheduled.last, 50);
    });

    test('adjust without a running rest does nothing', () async {
      await controller.adjust(RestTimer.step);

      expect(alerts.scheduled, isEmpty);
      expect(alerts.cancels, 0);
    });

    test('a running rest resumes with its end time', () async {
      await controller.start(90);
      final stored = controller.toDraft();

      now = now.add(const Duration(seconds: 30));
      final resumed = RestTimerController(alerts: alerts, clock: () => now);
      await resumed.restore(stored);

      expect(resumed.timer!.remainingSeconds(now), 60);
      expect(alerts.cancels, 0);
    });

    test('nothing stored clears any leftover alert', () async {
      await controller.restore(null);

      expect(controller.timer, isNull);
      expect(alerts.cancels, 1);
      expect(controller.toDraft(), isNull);
    });
  });
}
