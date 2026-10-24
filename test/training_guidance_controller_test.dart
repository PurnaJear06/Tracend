import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/guidance/training_guidance_controller.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';

import 'training_guidance_fixtures.dart';

DateTime _phoneNow() => DateTime(2026, 10, 24, 9);

void main() {
  test('it asks for the day the server named, never the phone\'s', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(repository.loads.single, DateTime(2026, 10, 2));
    expect(controller.current, isNotNull);
    expect(controller.loadFailure, isNull);
  });

  test('without the hub\'s day it asks the server for its today', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    var asked = 0;
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
      serverToday: () async {
        asked++;
        return DateTime(2026, 10, 2);
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(asked, 1);
    expect(repository.loads.single, DateTime(2026, 10, 2));
    // Known for the phone's day: not asked again.
    await controller.load();
    expect(asked, 1);
  });

  test('with no day and nobody to ask, nothing is sent', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(repository.loads, isEmpty);
    expect(controller.current, isNull);
    expect(controller.loadFailure, TrainingGuidanceFailure.network);
  });

  test('a day the server refuses is asked for again once it names the '
      'new one', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..loadError = const TrainingGuidanceException(
        TrainingGuidanceFailure.wrongDate,
      );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
      serverToday: () async {
        repository.loadError = null;
        repository.json = guidanceJson(
          'training_guidance_v1_1',
          date: '2026-10-03',
        );
        return DateTime(2026, 10, 3);
      },
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(repository.loads, [DateTime(2026, 10, 2), DateTime(2026, 10, 3)]);
    expect(controller.current!.localDate, '2026-10-03');
  });

  test('guidance for another day than the server\'s is never shown', () async {
    final repository = FakeGuidanceRepository(
      guidanceJson('training_guidance_v1_1', date: '2026-10-01'),
    );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(controller.current, isNull);
  });

  test('a failed read keeps what loaded before, an unreadable one drops '
      'it', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    repository.loadError = const TrainingGuidanceException(
      TrainingGuidanceFailure.network,
    );
    await controller.load();
    expect(controller.current, isNotNull);
    expect(controller.loadFailure, TrainingGuidanceFailure.network);
    repository.loadError = const TrainingGuidanceException(
      TrainingGuidanceFailure.unreadable,
    );
    await controller.load();
    expect(controller.current, isNull);
  });

  test('preparing a lighter week sends the known day and reads again, and '
      'applies nothing', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    expect(await controller.prepareDeload(), isNull);
    expect(repository.prepares, isEmpty, reason: 'no day known yet');
    await controller.load(localToday: DateTime(2026, 10, 2));
    final id = await controller.prepareDeload();
    expect(id, deloadProposalId);
    expect(repository.prepares.single, DateTime(2026, 10, 2));
    expect(controller.prepareFailure, isNull);
    expect(controller.preparing, isFalse);
  });

  test('a refusal is kept with its rule, and the guidance is read '
      'again', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.refused,
        code: 'plan_changed',
      );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(await controller.prepareDeload(), isNull);
    expect(controller.prepareFailure, TrainingGuidanceFailure.refused);
    expect(controller.prepareCode, 'plan_changed');
    await Future<void>.delayed(Duration.zero);
    expect(repository.loads.length, 2);
  });

  test('a lost connection is not followed by a read', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.network,
      );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    await controller.prepareDeload();
    await Future<void>.delayed(Duration.zero);
    expect(repository.loads.length, 1);
    expect(controller.prepareFailure, TrainingGuidanceFailure.network);
  });

  test('preparing asks the server for its day again when the phone\'s has '
      'changed', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    var phone = DateTime(2026, 10, 2, 22);
    var asked = 0;
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: () => phone,
      serverToday: () async {
        asked++;
        return DateTime(2026, 10, 3);
      },
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    // Midnight passed on the phone while the card was open.
    phone = DateTime(2026, 10, 3, 0, 5);
    await controller.prepareDeload();
    expect(asked, 1);
    expect(repository.prepares.single, DateTime(2026, 10, 3));
  });

  test(
    'a second request while the first is on its way sends nothing',
    () async {
      final repository = FakeGuidanceRepository(suggestedJson());
      final gate = Completer<void>();
      repository.prepareGate = gate.future;
      final controller = TrainingGuidanceController(
        repository: repository,
        clock: _phoneNow,
      );
      addTearDown(controller.dispose);
      await controller.load(localToday: DateTime(2026, 10, 2));
      final first = controller.prepareDeload();
      final second = controller.prepareDeload();
      expect(await second, isNull);
      gate.complete();
      expect(await first, deloadProposalId);
      expect(repository.prepares.length, 1);
    },
  );

  test('a change waiting in Coach is kept as such, and the guidance is not '
      'read again for it', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.otherProposalPending,
      );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(await controller.prepareDeload(), isNull);
    expect(
      controller.prepareFailure,
      TrainingGuidanceFailure.otherProposalPending,
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.loads.length, 1);
  });

  test('a failure that is not an Exception still ends the request', () async {
    final repository = FakeGuidanceRepository(suggestedJson());
    var phone = DateTime(2026, 10, 2, 22);
    var broken = true;
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: () => phone,
      serverToday: () async {
        if (broken) throw StateError('the day could not be read');
        return DateTime(2026, 10, 3);
      },
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    // Midnight passed, so the day is asked for again, and that throws.
    phone = DateTime(2026, 10, 3, 0, 5);
    expect(await controller.prepareDeload(), isNull);
    expect(controller.preparing, isFalse);
    expect(controller.prepareFailure, TrainingGuidanceFailure.network);
    expect(repository.prepares, isEmpty);
    // Nothing is stuck: the next tap works.
    broken = false;
    expect(await controller.prepareDeload(), deloadProposalId);
    expect(controller.preparing, isFalse);
    expect(controller.prepareFailure, isNull);
    expect(repository.prepares.single, DateTime(2026, 10, 3));
  });

  test('a read that throws an Error ends loading too', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..loadThrows = StateError('boom');
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(controller.loading, isFalse);
    expect(controller.loadFailure, TrainingGuidanceFailure.network);
  });
}
