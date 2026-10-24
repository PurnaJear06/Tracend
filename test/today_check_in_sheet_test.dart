import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/check_in_sheet.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

class _Recorder {
  _Recorder({this.delivers = true, this.refuses = false});

  final bool delivers;

  /// The server refuses the check-in (22023), as for pain on a day it does
  /// not record.
  final bool refuses;
  final payloads = <Map<String, dynamic>>[];

  Future<bool> send(
    String localDate,
    String timezone,
    String idempotencyKey,
    Map<String, dynamic> payload,
  ) async {
    payloads.add(Map<String, dynamic>.from(payload));
    if (refuses) {
      throw const PostgrestException(message: 'refused', code: '22023');
    }
    return delivers;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Recorder recorder, {
  List<JointState> jointStates = const [],
  void Function(CheckInSaved?)? onSaved,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final saved = await showCheckInSheet(
                  context,
                  _environment,
                  sender: recorder.send,
                  jointStates: jointStates,
                );
                onSaved?.call(saved);
              },
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

    testWidgets('some pain asks how strong, where and the red-flag question '
        'before it saves', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Pain: Some pain');
      await _save(tester);
      expect(recorder.payloads, isEmpty);
      expect(
        find.text('Choose how strong the pain is to save.'),
        findsOneWidget,
      );
      expect(find.text('Choose where the pain is to save.'), findsOneWidget);

      await _choose(tester, 'Pain 4 of 10');
      await _save(tester);
      expect(recorder.payloads, isEmpty);
      expect(find.text('Choose where the pain is to save.'), findsOneWidget);

      await _choose(tester, 'Where is it?: Knee');
      await _save(tester);
      expect(recorder.payloads, isEmpty);
      expect(
        find.text('Choose any that apply, or None of these.'),
        findsOneWidget,
      );

      await _choose(tester, 'Do any of these apply?: None of these');
      await _save(tester);
      final payload = recorder.payloads.single;
      expect(payload['pain_severity'], 4);
      expect(payload['pain_area'], 'knee');
      expect(payload['pain_red_flags'], isEmpty);
      expect(payload.containsKey('pain_pattern'), isFalse);
    });

    testWidgets('going back to no pain stores 0', (tester) async {
      final recorder = _Recorder();
      await _open(tester, recorder);

      await _choose(tester, 'Pain: Some pain');
      await _choose(tester, 'Pain 4 of 10');
      await _choose(tester, 'Where is it?: Knee');
      await _choose(tester, 'Pain: No pain');
      await _save(tester);

      final payload = recorder.payloads.single;
      expect(payload['pain_severity'], 0);
      expect(
        payload.keys.where((key) => key != 'pain_severity'),
        [
          'sleep_quality',
          'energy',
          'soreness',
          'hunger',
          'mood',
          'available_to_train',
          'note',
        ],
        reason: 'no pain answer travels once the pain is taken back',
      );
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

  group('the pain check in the check-in', () {
    Future<void> hurt(
      WidgetTester tester, {
      required int strength,
      required String area,
    }) async {
      await _choose(tester, 'Pain: Some pain');
      await _choose(tester, 'Pain $strength of 10');
      await _choose(tester, 'Where is it?: $area');
    }

    testWidgets('red flags are ticked, sent sorted and routed out', (
      tester,
    ) async {
      final recorder = _Recorder();
      CheckInSaved? saved;
      await _open(tester, recorder, onSaved: (value) => saved = value);
      await hurt(tester, strength: 3, area: 'Lower back');
      await _choose(tester, 'When does it hurt?: Even at rest');
      await _choose(
        tester,
        'Do any of these apply?: Numbness, tingling or weakness in an arm or '
        'leg',
      );
      await _save(tester);

      final payload = recorder.payloads.single;
      expect(payload['pain_area'], 'back');
      expect(payload['pain_pattern'], 'rest');
      expect(payload['pain_red_flags'], ['numb_weak_limb']);
      expect(saved!.delivered, isTrue);
      expect(saved!.referralRoute, 'clinician_today');
    });

    testWidgets('an urgent flag is the strictest route', (tester) async {
      final recorder = _Recorder();
      CheckInSaved? saved;
      await _open(tester, recorder, onSaved: (value) => saved = value);
      await hurt(tester, strength: 2, area: 'Lower back');
      await _choose(
        tester,
        'Do any of these apply?: New trouble controlling your bladder or '
        'bowels, or numbness around your groin or inner thighs',
      );
      await _choose(
        tester,
        'Do any of these apply?: Numbness, tingling or weakness in an arm or '
        'leg',
      );
      await _save(tester);
      expect(saved!.referralRoute, 'urgent');
    });

    testWidgets('None of these clears the ticks, and a tick clears None', (
      tester,
    ) async {
      final recorder = _Recorder();
      await _open(tester, recorder);
      await hurt(tester, strength: 4, area: 'Knee');
      await _choose(tester, 'Do any of these apply?: It swelled up quickly');
      await _choose(tester, 'Do any of these apply?: None of these');
      await _save(tester);
      expect(recorder.payloads.single['pain_red_flags'], isEmpty);
    });

    testWidgets('changing the area drops the answers it does not ask', (
      tester,
    ) async {
      final recorder = _Recorder();
      await _open(tester, recorder);
      await hurt(tester, strength: 4, area: 'Knee');
      await _choose(
        tester,
        'Do any of these apply?: The knee locks or gives way',
      );
      await _choose(tester, 'Where is it?: Shoulder');
      await _save(tester);
      expect(recorder.payloads, isEmpty, reason: 'the red-flag answer is open');
      expect(
        find.text('Choose any that apply, or None of these.'),
        findsOneWidget,
      );
    });

    testWidgets('an undelivered report is kept and said so, with its flags', (
      tester,
    ) async {
      final recorder = _Recorder(delivers: false);
      CheckInSaved? saved;
      await _open(tester, recorder, onSaved: (value) => saved = value);
      await hurt(tester, strength: 8, area: 'Knee');
      await _choose(tester, 'Do any of these apply?: None of these');
      await _save(tester);

      expect(saved!.delivered, isFalse);
      expect(saved!.referralRoute, 'clinician_today');
      expect(
        find.text(
          'Saved on this phone. Your pain report has not reached Tracend yet.',
        ),
        findsOneWidget,
      );
      final preferences = await SharedPreferences.getInstance();
      final queue = CheckInQueue(preferences);
      expect(queue.painState, CheckInPainState.waiting);
      Map<String, dynamic>? replayed;
      await queue.replay((date, zone, key, payload) async {
        replayed = payload;
        return true;
      });
      expect(replayed!['pain_area'], 'knee');
      expect(replayed!['pain_red_flags'], isEmpty);
    });

    testWidgets('a refusal keeps the sheet open and says so, never queues', (
      tester,
    ) async {
      final recorder = _Recorder(refuses: true);
      await _open(tester, recorder);
      await hurt(tester, strength: 5, area: 'Knee');
      await _choose(tester, 'Do any of these apply?: None of these');
      await _save(tester);

      expect(
        find.textContaining('Tracend could not record these pain answers'),
        findsOneWidget,
      );
      expect(find.text('Save check-in'), findsOneWidget, reason: 'still open');
      final preferences = await SharedPreferences.getInstance();
      expect(CheckInQueue(preferences).painState, CheckInPainState.none);
    });

    testWidgets('an area already noted asks how it is today', (tester) async {
      final recorder = _Recorder();
      await _open(
        tester,
        recorder,
        jointStates: const [
          JointState(
            area: PainArea.knee,
            state: JointStateKind.limited,
            severity: 5,
            persistent: false,
          ),
        ],
      );
      expect(
        find.text('Last time you noted knee pain. How is it today?'),
        findsOneWidget,
      );
      await _choose(
        tester,
        'Last time you noted knee pain. How is it today?: Gone',
      );
      await _save(tester);
      expect(recorder.payloads.single['pain_followups'], [
        {'area': 'knee', 'severity': 0, 'cleared_by_clinician': false},
      ]);
      expect(recorder.payloads.single.containsKey('pain_area'), isFalse);
    });

    testWidgets('still there asks how strong before it saves', (tester) async {
      final recorder = _Recorder();
      await _open(
        tester,
        recorder,
        jointStates: const [
          JointState(
            area: PainArea.knee,
            state: JointStateKind.limited,
            severity: 5,
            persistent: false,
          ),
        ],
      );
      await _choose(
        tester,
        'Last time you noted knee pain. How is it today?: Still there',
      );
      await _save(tester);
      expect(recorder.payloads, isEmpty);
      expect(find.text('Choose how strong it is now to save.'), findsOneWidget);
      await _choose(tester, 'Pain 7 of 10');
      await _save(tester);
      expect(recorder.payloads.single['pain_followups'], [
        {'area': 'knee', 'severity': 7, 'cleared_by_clinician': false},
      ]);
    });

    testWidgets('a held area asks whether a doctor or physio cleared it', (
      tester,
    ) async {
      final recorder = _Recorder();
      await _open(
        tester,
        recorder,
        jointStates: const [
          JointState(
            area: PainArea.shoulder,
            state: JointStateKind.held,
            severity: 8,
            persistent: false,
            holdOutcome: 'clinician_today',
          ),
        ],
      );
      expect(
        find.text('Has a doctor or physio cleared you to train your shoulder?'),
        findsOneWidget,
      );
      await _choose(
        tester,
        'Has a doctor or physio cleared you to train your shoulder?: Yes',
      );
      await _choose(tester, 'Pain 1 of 10');
      await _save(tester);
      expect(recorder.payloads.single['pain_followups'], [
        {'area': 'shoulder', 'severity': 1, 'cleared_by_clinician': true},
      ]);
    });

    testWidgets('Not yet sends nothing for a held area', (tester) async {
      final recorder = _Recorder();
      await _open(
        tester,
        recorder,
        jointStates: const [
          JointState(
            area: PainArea.shoulder,
            state: JointStateKind.held,
            severity: 8,
            persistent: false,
            holdOutcome: 'clinician_today',
          ),
        ],
      );
      await _choose(
        tester,
        'Has a doctor or physio cleared you to train your shoulder?: Not yet',
      );
      await _save(tester);
      expect(recorder.payloads.single.containsKey('pain_followups'), isFalse);
    });
  });
}
