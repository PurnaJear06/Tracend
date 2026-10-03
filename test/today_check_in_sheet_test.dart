import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/check_in_sheet.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

class _Recorder {
  _Recorder({this.delivers = true});

  final bool delivers;
  final payloads = <Map<String, dynamic>>[];

  Future<bool> send(
    String localDate,
    String timezone,
    String idempotencyKey,
    Map<String, dynamic> payload,
  ) async {
    payloads.add(Map<String, dynamic>.from(payload));
    return delivers;
  }
}

Future<void> _open(WidgetTester tester, _Recorder recorder) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showCheckInSheet(
                context,
                _environment,
                sender: recorder.send,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  final option = find.bySemanticsLabel(label);
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save check-in'));
  await tester.pumpAndSettle();
}

void main() {
  group('CheckInScale', () {
    test('every scale has five labels stored as 1 to 5', () {
      for (final scale in checkInScales) {
        expect(scale.labels, hasLength(5), reason: scale.key);
        expect([for (var i = 0; i < 5; i++) scale.valueAt(i)]..sort(), [
          1,
          2,
          3,
          4,
          5,
        ]);
      }
    });

    test('soreness is reversed: Great means not sore', () {
      final soreness = checkInScales.singleWhere((s) => s.key == 'soreness');
      expect(soreness.reversed, isTrue);
      expect(soreness.labelFor(1), 'Great, not sore');
      expect(soreness.labelFor(5), 'Very sore');
      expect(soreness.valueAt(0), 5);
      expect(soreness.valueAt(4), 1);
    });

    test('energy runs from Very low (1) to Great (5)', () {
      final energy = checkInScales.singleWhere((s) => s.key == 'energy');
      expect(energy.labels, ['Very low', 'Low', 'OK', 'Good', 'Great']);
      expect(energy.labelFor(1), 'Very low');
      expect(energy.labelFor(5), 'Great');
    });
  });

  group('Check-in sheet', () {
    testWidgets('saves the unchanged defaults with the same payload shape', (
      tester,
    ) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      expect(find.text('Daily check-in'), findsOneWidget);
      expect(find.bySemanticsLabel('Energy: OK'), findsOneWidget);
      await _save(tester);

      expect(recorder.payloads.single, {
        'sleep_quality': 3,
        'energy': 3,
        'soreness': 3,
        'hunger': 3,
        'mood': 3,
        'pain_severity': 0,
        'available_to_train': true,
        'note': '',
      });
      expect(find.text('Daily check-in'), findsNothing);
      expect(find.text('Check-in saved'), findsOneWidget);
    });

    testWidgets('labelled answers store their 1–5 values', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Sleep quality: Very poor');
      await _choose(tester, 'Energy: Great');
      await _choose(tester, 'Soreness: Great, not sore');
      await _choose(tester, 'Hunger: Hungry');
      await _choose(tester, 'Mood: Good');
      await _save(tester);

      final payload = recorder.payloads.single;
      expect(payload['sleep_quality'], 1);
      expect(payload['energy'], 5);
      expect(payload['soreness'], 1);
      expect(payload['hunger'], 4);
      expect(payload['mood'], 4);
    });

    testWidgets('Very sore stores the top soreness value', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Soreness: Very sore');
      await _save(tester);

      expect(recorder.payloads.single['soreness'], 5);
    });

    testWidgets('the selected answer is marked for VoiceOver', (tester) async {
      await _open(tester, _Recorder());
      await _choose(tester, 'Energy: Good');

      final node = tester.getSemantics(find.bySemanticsLabel('Energy: Good'));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('some pain asks how strong before it saves', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Pain: Some pain');
      await _save(tester);
      expect(recorder.payloads, isEmpty);
      expect(
        find.text('Choose how strong the pain is to save.'),
        findsOneWidget,
      );

      await _choose(tester, 'Pain 7 of 10');
      await _save(tester);
      expect(recorder.payloads.single['pain_severity'], 7);
    });

    testWidgets('going back to no pain stores 0', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Pain: Some pain');
      await _choose(tester, 'Pain 4 of 10');
      await _choose(tester, 'Pain: No pain');
      await _save(tester);

      expect(recorder.payloads.single['pain_severity'], 0);
    });

    testWidgets('the note counter appears only near the limit', (tester) async {
      await _open(tester, _Recorder());
      final note = find.byType(TextField);
      await tester.ensureVisible(note);

      await tester.enterText(note, 'Slept badly.');
      await tester.pump();
      expect(find.textContaining('characters left'), findsNothing);

      await tester.enterText(note, 'a' * 950);
      await tester.pump();
      expect(find.text('50 characters left'), findsOneWidget);
    });

    testWidgets('an undelivered check-in stays queued on the device', (
      tester,
    ) async {
      final recorder = _Recorder(delivers: false);
      await _open(tester, recorder);
      await _save(tester);

      expect(
        find.text(
          'Check-in saved on this device. It will sync when you are online.',
        ),
        findsOneWidget,
      );
      final preferences = await SharedPreferences.getInstance();
      final outcome = await CheckInQueue(
        preferences,
      ).replay((date, zone, key, payload) async => true);
      expect(outcome, CheckInReplayOutcome.delivered);
    });

    testWidgets('Save stays reachable at 320pt with 2× text', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final recorder = _Recorder();
      await _open(tester, recorder);

      expect(tester.takeException(), isNull);
      // No scrolling: the button is pinned below the questions.
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();
      expect(recorder.payloads, hasLength(1));
    });
  });
}
