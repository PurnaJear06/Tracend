import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/cycle/cycle_labels.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';

import 'cycle_fakes.dart';

void main() {
  group('cycleTodayLine', () {
    test('names the cycle day and the expected range', () {
      expect(
        cycleTodayLine(
          trackingAnswer(
            state: CycleState(
              cycleDay: 18,
              phase: CyclePhase.secondHalf,
              expectedFrom: DateTime(2026, 12, 8),
              expectedTo: DateTime(2026, 12, 12),
            ),
          ),
        ),
        'Cycle day 18 · period expected 8–12 Dec',
      );
    });

    test('a range across months names both months', () {
      expect(
        cycleDateRange(DateTime(2026, 11, 30), DateTime(2026, 12, 3)),
        '30 Nov–3 Dec',
      );
      expect(
        cycleDateRange(DateTime(2026, 12, 8), DateTime(2026, 12, 8)),
        '8 Dec',
      );
    });

    test('an irregular cycle with no range is the cycle day alone', () {
      expect(
        cycleTodayLine(
          trackingAnswer(
            status: CycleStatus.irregular,
            state: const CycleState(cycleDay: 18),
          ),
        ),
        'Cycle day 18',
      );
    });

    test('a period in progress is the period day', () {
      expect(
        cycleTodayLine(
          trackingAnswer(state: const CycleState(cycleDay: 2, periodDay: 2)),
        ),
        'Period day 2',
      );
    });

    test('a late period says how late', () {
      expect(
        cycleTodayLine(
          trackingAnswer(state: const CycleState(cycleDay: 34, lateDays: 4)),
        ),
        'Period is 4 days later than usual',
      );
      expect(
        cycleTodayLine(
          trackingAnswer(state: const CycleState(cycleDay: 31, lateDays: 1)),
        ),
        'Period is 1 day later than usual',
      );
    });

    test('contraception shows only a bleed today', () {
      expect(
        cycleTodayLine(
          trackingAnswer(
            status: CycleStatus.hormonalContraception,
            state: const CycleState(periodDay: 2),
          ),
        ),
        'Bleed day 2',
      );
      expect(
        cycleTodayLine(
          trackingAnswer(status: CycleStatus.hormonalContraception),
        ),
        isNull,
      );
    });

    test('there is no line when there is nothing honest to say', () {
      expect(cycleTodayLine(CycleAnswer.off), isNull);
      expect(
        cycleTodayLine(trackingAnswer(status: CycleStatus.noPeriods)),
        isNull,
      );
      expect(cycleTodayLine(trackingAnswer()), isNull);
      expect(
        cycleTodayLine(const CycleAnswer(state: CycleState(cycleDay: 4))),
        isNull,
      );
    });
  });

  group('notes', () {
    test('the recovery note needs the second half and some confidence', () {
      CycleAnswer answer(CyclePhase? phase, CycleConfidence? confidence) =>
          trackingAnswer(
            state: CycleState(phase: phase, confidence: confidence),
          );
      expect(
        cycleRecoveryNote(
          answer(CyclePhase.secondHalf, CycleConfidence.medium),
        ),
        'Second half of your cycle: resting heart rate often runs a little '
        "higher and HRV a little lower. That's expected.",
      );
      expect(
        cycleRecoveryNote(answer(CyclePhase.secondHalf, CycleConfidence.high)),
        isNotNull,
      );
      expect(
        cycleRecoveryNote(answer(CyclePhase.secondHalf, CycleConfidence.low)),
        isNull,
      );
      expect(
        cycleRecoveryNote(answer(CyclePhase.firstHalf, CycleConfidence.high)),
        isNull,
      );
      expect(cycleRecoveryNote(CycleAnswer.off), isNull);
    });

    test('the weight note follows the water window', () {
      expect(
        cycleWeightNote(
          trackingAnswer(state: const CycleState(weightWaterWindow: true)),
        ),
        'Weight often runs higher around a period (water). Compare with the '
        'same point last cycle.',
      );
      expect(cycleWeightNote(trackingAnswer()), isNull);
      expect(cycleWeightNote(CycleAnswer.off), isNull);
    });

    test('the long-gap message names 3 or 6 months', () {
      expect(
        cycleLongGapMessage(
          trackingAnswer(state: const CycleState(noPeriodLong: true)),
        ),
        "No period logged for 3 months. If that's not expected for you, "
        "it's worth talking to a doctor.",
      );
      expect(
        cycleLongGapMessage(
          trackingAnswer(
            status: CycleStatus.irregular,
            state: const CycleState(noPeriodLong: true),
          ),
        ),
        contains('6 months'),
      );
      expect(cycleLongGapMessage(trackingAnswer()), isNull);
    });
  });

  test('a refused call is worded, never shown as its code', () {
    for (final reason in CycleRefusal.values) {
      final message = cycleFailureMessage(
        CycleRefused(reason),
        fallback: 'fallback',
      );
      expect(message, isNot('fallback'));
      expect(message, isNot(contains(reason.code)));
      expect(message, isNot(contains('_')));
    }
    expect(
      cycleFailureMessage(Exception('x'), fallback: 'fallback'),
      'fallback',
    );
  });
}
