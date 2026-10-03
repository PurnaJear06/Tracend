import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';

const _restIdentifier = 'tracend.rest-timer';

/// Plays the native side of `com.tracend.app/notifications` as
/// `ios/Runner/SceneDelegate.swift` implements it: pending requests are
/// keyed by identifier, so one identifier holds one alert.
class _NativeNotifications {
  final calls = <MethodCall>[];
  final pending = <String, int>{};
  String authorization = 'authorized';
  bool daily = false;
  bool weekly = false;
  bool rest = false;

  Map<String, Object> get _state => {
    'authorization_status': authorization,
    'daily_check_in': daily,
    'weekly_review': weekly,
    'rest_timer_alerts': rest,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final arguments = call.arguments is Map
        ? Map<String, Object?>.from(call.arguments as Map)
        : const <String, Object?>{};
    switch (call.method) {
      case 'status':
        return _state;
      case 'configure':
        daily = arguments['daily_check_in']! as bool;
        weekly = arguments['weekly_review']! as bool;
        rest = arguments['rest_timer_alerts']! as bool;
        // Reconciliation replaces only the reminders it owns.
        pending
          ..remove('tracend.daily-check-in')
          ..remove('tracend.weekly-review');
        if (daily) pending['tracend.daily-check-in'] = 0;
        if (weekly) pending['tracend.weekly-review'] = 0;
        return _state;
      case 'scheduleRestAlert':
        if (!rest || authorization != 'authorized') return false;
        pending[_restIdentifier] = arguments['seconds']! as int;
        return true;
      case 'cancelRestAlert':
        pending.remove(_restIdentifier);
        return null;
    }
    throw MissingPluginException();
  }

  List<String> get methods => [for (final call in calls) call.method];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeNotifications native;
  late List<Breadcrumb> breadcrumbs;

  setUp(() {
    native = _NativeNotifications();
    breadcrumbs = [];
    AppBreadcrumbs.sink = breadcrumbs.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, native.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
  });

  test('the channel name is the one SceneDelegate registers', () {
    expect(notificationChannel.name, 'com.tracend.app/notifications');
  });

  group('status and configure', () {
    test('round-trip all three toggles', () async {
      const repository = MethodChannelNotificationRepository();

      final saved = await repository.configure(
        dailyCheckIn: true,
        weeklyReview: false,
        restTimerAlertsEnabled: true,
      );
      expect(native.calls.single.arguments, {
        'daily_check_in': true,
        'weekly_review': false,
        'rest_timer_alerts': true,
      });
      expect(saved.dailyCheckIn, isTrue);
      expect(saved.weeklyReview, isFalse);
      expect(saved.restTimerAlertsEnabled, isTrue);

      final loaded = await repository.load();
      expect(loaded.dailyCheckIn, isTrue);
      expect(loaded.weeklyReview, isFalse);
      expect(loaded.restTimerAlertsEnabled, isTrue);
      expect(loaded.isAuthorized, isTrue);
    });

    test('a state without the rest toggle is refused', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            notificationChannel,
            (_) async => {
              'authorization_status': 'authorized',
              'daily_check_in': true,
              'weekly_review': true,
            },
          );
      await expectLater(
        const MethodChannelNotificationRepository().load(),
        throwsFormatException,
      );
    });

    test('reminder reconciliation leaves a running rest alert', () async {
      const repository = MethodChannelNotificationRepository();
      await repository.configure(
        dailyCheckIn: false,
        weeklyReview: false,
        restTimerAlertsEnabled: true,
      );
      await const MethodChannelRestAlertScheduler().scheduleRestAlert(90);

      await repository.configure(
        dailyCheckIn: true,
        weeklyReview: true,
        restTimerAlertsEnabled: true,
      );

      expect(native.pending[_restIdentifier], 90);
      expect(native.methods, isNot(contains('cancelRestAlert')));
    });

    test('turning rest alerts off cancels the pending alert', () async {
      const repository = MethodChannelNotificationRepository();
      await repository.configure(
        dailyCheckIn: true,
        weeklyReview: false,
        restTimerAlertsEnabled: true,
      );
      await const MethodChannelRestAlertScheduler().scheduleRestAlert(60);

      await repository.configure(
        dailyCheckIn: true,
        weeklyReview: false,
        restTimerAlertsEnabled: false,
      );

      expect(native.methods.last, 'cancelRestAlert');
      expect(native.pending.containsKey(_restIdentifier), isFalse);
      expect(native.pending.containsKey('tracend.daily-check-in'), isTrue);
    });
  });

  group('rest alert', () {
    setUp(() => native.rest = true);

    test('scheduling twice leaves one alert with the latest time', () async {
      const alerts = MethodChannelRestAlertScheduler();

      expect(await alerts.scheduleRestAlert(90), isTrue);
      expect(await alerts.scheduleRestAlert(120), isTrue);

      expect(native.methods, ['scheduleRestAlert', 'scheduleRestAlert']);
      expect(native.calls.last.arguments, {'seconds': 120});
      expect(native.pending, {_restIdentifier: 120});
    });

    test('is not scheduled when rest alerts are off', () async {
      native.rest = false;
      expect(
        await const MethodChannelRestAlertScheduler().scheduleRestAlert(90),
        isFalse,
      );
      expect(native.pending, isEmpty);
    });

    test('caps the delay and refuses a rest that has already ended', () async {
      const alerts = MethodChannelRestAlertScheduler();

      await alerts.scheduleRestAlert(99999);
      expect(native.calls.last.arguments, {'seconds': 3600});

      expect(await alerts.scheduleRestAlert(0), isFalse);
      expect(native.methods.last, 'cancelRestAlert');
    });

    test('a platform failure never reaches the workout', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            notificationChannel,
            (_) async => throw PlatformException(code: 'schedule_failed'),
          );
      const alerts = MethodChannelRestAlertScheduler();
      expect(await alerts.scheduleRestAlert(90), isFalse);
      await alerts.cancelRestAlert();
    });

    test('scheduling leaves a breadcrumb without the rest length', () async {
      await const MethodChannelRestAlertScheduler().scheduleRestAlert(90);

      final crumb = breadcrumbs.single;
      expect(crumb.category, 'workout');
      expect(crumb.message, 'Rest alert scheduled');
      expect(crumb.data, {'scheduled': true});
    });
  });

  group('every way a rest ends early cancels the alert', () {
    late DateTime now;
    late RestTimerController controller;

    setUp(() async {
      native.rest = true;
      now = DateTime.utc(2026, 10, 3, 9);
      controller = RestTimerController(
        alerts: const MethodChannelRestAlertScheduler(),
        clock: () => now,
      );
      await controller.start(90);
      expect(native.pending, {_restIdentifier: 90});
    });

    Future<void> expectCancelled() async {
      expect(native.methods.last, 'cancelRestAlert');
      expect(native.pending, isEmpty);
      expect(controller.timer, isNull);
    }

    test('skip', () async {
      await controller.skip();
      await expectCancelled();
    });

    test('finish, discard, or leave without saving', () async {
      await controller.stop();
      await expectCancelled();
    });

    test('-15 s past the end', () async {
      now = now.add(const Duration(seconds: 80));
      await controller.adjust(-RestTimer.step);
      await expectCancelled();
    });

    test('resume after the rest ended', () async {
      final stored = controller.toDraft();
      now = now.add(const Duration(minutes: 5));
      final resumed = RestTimerController(
        alerts: const MethodChannelRestAlertScheduler(),
        clock: () => now,
      );
      await resumed.restore(stored);
      expect(native.methods.last, 'cancelRestAlert');
      expect(native.pending, isEmpty);
      expect(resumed.timer, isNull);
    });

    test('+15 s moves the one alert instead of adding one', () async {
      now = now.add(const Duration(seconds: 30));
      await controller.adjust(RestTimer.step);
      expect(native.pending, {_restIdentifier: 75});
      expect(native.methods, isNot(contains('cancelRestAlert')));
    });
  });
}
