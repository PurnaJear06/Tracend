import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';

import 'day_adjustment_fixtures.dart';

void main() {
  late DateTime device;
  late FakeDayAdjustmentRepository repository;
  var asks = 0;
  DateTime? server;

  DayAdjustmentController make({bool withServer = true}) =>
      DayAdjustmentController(
        repository: repository,
        clock: () => device,
        serverToday: withServer
            ? () async {
                asks++;
                return server;
              }
            : null,
      );

  setUp(() {
    device = DateTime(2026, 10, 2, 9);
    server = DateTime(2026, 10, 2);
    asks = 0;
    repository = FakeDayAdjustmentRepository(adjustmentJson());
  });

  test('reads for the server\'s day, never the phone\'s', () async {
    device = DateTime(2026, 10, 2, 23, 50); // the phone is a day ahead
    server = DateTime(2026, 10, 1);
    repository.json = adjustmentJson(day: '2026-10-01');
    final controller = make();
    await controller.load();
    expect(repository.loads.single, DateTime(2026, 10, 1));
    expect(controller.current?.localDate, '2026-10-01');
  });

  test('the hub\'s local_today replaces what was known', () async {
    final controller = make();
    await controller.load();
    server = DateTime(2026, 10, 9);
    repository.json = adjustmentJson(day: '2026-10-09');
    await controller.load(localToday: DateTime(2026, 10, 9));
    expect(repository.loads.last, DateTime(2026, 10, 9));
    expect(asks, 1, reason: 'the hub\'s day needs no second question');
  });

  test('without a server day nothing is read', () async {
    final controller = make(withServer: false);
    await controller.load();
    expect(repository.loads, isEmpty);
    expect(controller.current, isNull);
    expect(controller.loadFailure, DayAdjustmentFailure.network);
  });

  test(
    'an adjustment for another day than the server\'s is not shown',
    () async {
      repository.json = adjustmentJson(day: '2026-10-03');
      final controller = make();
      await controller.load();
      expect(controller.current, isNull);
      expect(await controller.respond(accept: true), isFalse);
      expect(repository.responses, isEmpty);
    },
  );

  test('a new phone day asks the server again', () async {
    final controller = make();
    await controller.load();
    device = DateTime(2026, 10, 3, 7);
    server = DateTime(2026, 10, 3);
    repository.json = adjustmentJson(day: '2026-10-03');
    await controller.load();
    expect(asks, 2);
    expect(repository.loads.last, DateTime(2026, 10, 3));
  });

  test('a refused date asks the server and reads again once', () async {
    final refusing = _RefusesFirst(repository);
    final other = DayAdjustmentController(
      repository: refusing,
      clock: () => device,
      serverToday: () async => DateTime(2026, 10, 2),
    );
    await other.load(localToday: DateTime(2026, 10, 1));
    expect(refusing.days, [DateTime(2026, 10, 1), DateTime(2026, 10, 2)]);
    expect(other.current?.localDate, '2026-10-02');
  });

  test('an answer is sent for the day on screen', () async {
    final controller = make();
    await controller.load();
    expect(await controller.respond(accept: true), isTrue);
    expect(repository.responses.single.day, DateTime(2026, 10, 2));
    expect(controller.current?.isAccepted, isTrue);
    expect(controller.busy, isFalse);
  });

  test('a chosen kind travels with the answer', () async {
    final controller = make();
    await controller.load();
    await controller.respond(
      accept: true,
      chosen: DayAdjustmentKind.swapToEasyCardio,
    );
    expect(
      repository.responses.single.chosen,
      DayAdjustmentKind.swapToEasyCardio,
    );
    expect(controller.current?.kind, DayAdjustmentKind.swapToEasyCardio);
  });

  test('a refused answer reads the day again so the card is true', () async {
    final controller = make();
    await controller.load();
    repository
      ..respondError = const DayAdjustmentException(
        DayAdjustmentFailure.unavailable,
      )
      ..json = adjustmentJson(
        status: 'accepted',
        origin: 'proposed',
        available: false,
        unavailable: 'session_started',
      );
    expect(await controller.respond(accept: true), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(controller.answerFailure, DayAdjustmentFailure.unavailable);
    expect(controller.current?.sessionBegun, isTrue);
  });

  test('a network failure keeps what shows and does not reread', () async {
    final controller = make();
    await controller.load();
    final reads = repository.loads.length;
    repository.respondError = const DayAdjustmentException(
      DayAdjustmentFailure.network,
    );
    expect(await controller.respond(accept: true), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(repository.loads.length, reads);
    expect(controller.current?.status, DayAdjustmentStatus.proposed);
  });

  test('a read is refreshed only when old', () async {
    final controller = make();
    await controller.load();
    final reads = repository.loads.length;
    await controller.refreshIfStale();
    expect(repository.loads.length, reads);
    device = device.add(const Duration(minutes: 31));
    await controller.refreshIfStale();
    expect(repository.loads.length, reads + 1);
  });

  test('a failed refresh keeps the earlier answer on screen', () async {
    final controller = make();
    await controller.load();
    repository.loadError = const DayAdjustmentException(
      DayAdjustmentFailure.network,
    );
    await controller.load();
    expect(controller.current, isNotNull);
    expect(controller.loadFailure, DayAdjustmentFailure.network);
  });
}

/// Refuses the first date it is asked for, as the server does when its day
/// moved on, then answers like [inner].
class _RefusesFirst implements DayAdjustmentRepository {
  _RefusesFirst(this.inner);
  final FakeDayAdjustmentRepository inner;
  final days = <DateTime>[];

  @override
  Future<DayAdjustment> load(DateTime localToday) async {
    days.add(localToday);
    if (days.length == 1) {
      throw const DayAdjustmentException(DayAdjustmentFailure.wrongDate);
    }
    inner.json = adjustmentJson(day: '2026-10-02');
    return inner.load(localToday);
  }

  @override
  Future<DayAdjustment> respond(
    DateTime localToday, {
    required bool accept,
    DayAdjustmentKind? chosen,
  }) => inner.respond(localToday, accept: accept, chosen: chosen);
}
