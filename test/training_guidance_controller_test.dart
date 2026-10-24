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

  test('a refusal is kept with its words, and the guidance is read '
      'again', () async {
    final repository = FakeGuidanceRepository(suggestedJson())
      ..prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.refused,
        reason: 'Your plan changed.',
      );
    final controller = TrainingGuidanceController(
      repository: repository,
      clock: _phoneNow,
    );
    addTearDown(controller.dispose);
    await controller.load(localToday: DateTime(2026, 10, 2));
    expect(await controller.prepareDeload(), isNull);
    expect(controller.prepareFailure, TrainingGuidanceFailure.refused);
    expect(controller.prepareReason, 'Your plan changed.');
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
}
