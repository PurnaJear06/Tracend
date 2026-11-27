import 'package:tracend/features/cycle/cycle_repository.dart';

// The words the cycle screens use, in one place so Today, Account, onboarding
// and the check-in say the same thing (UX_FLOWS.md §14).

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "8 Dec".
String cycleDayMonth(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// "8–12 Dec", "30 Nov–3 Dec" or "8 Dec" for one day.
String cycleDateRange(DateTime from, DateTime to) {
  if (from == to) return cycleDayMonth(from);
  if (from.month == to.month && from.year == to.year) {
    return '${from.day}–${cycleDayMonth(to)}';
  }
  return '${cycleDayMonth(from)}–${cycleDayMonth(to)}';
}

String cycleStatusLabel(CycleStatus status) => switch (status) {
  CycleStatus.regular => 'Regular periods',
  CycleStatus.irregular => 'Irregular or changing (for example perimenopause)',
  CycleStatus.hormonalContraception =>
    'Hormonal contraception (pill, implant, hormonal IUD, injection, ring or '
        'patch)',
  CycleStatus.noPeriods => 'No periods at the moment',
};

/// The status in a few words, for a row's value.
String cycleStatusShort(CycleStatus status) => switch (status) {
  CycleStatus.regular => 'Regular periods',
  CycleStatus.irregular => 'Irregular or changing',
  CycleStatus.hormonalContraception => 'Hormonal contraception',
  CycleStatus.noPeriods => 'No periods at the moment',
};

String periodFlowLabel(PeriodFlow flow) => switch (flow) {
  PeriodFlow.spotting => 'Spotting',
  PeriodFlow.light => 'Light',
  PeriodFlow.medium => 'Medium',
  PeriodFlow.heavy => 'Heavy',
  PeriodFlow.unspecified => 'Period',
};

String cycleCrampsLabel(CycleCramps cramps) => switch (cramps) {
  CycleCramps.none => 'None',
  CycleCramps.mild => 'Mild',
  CycleCramps.strong => 'Strong',
};

/// The one line Today shows, or null when there is nothing honest to say:
/// tracking off, no periods, contraception without a bleed today, or no data.
String? cycleTodayLine(CycleAnswer answer) {
  final status = answer.status;
  if (!answer.trackingEnabled || status == null) return null;
  final state = answer.state;
  switch (status) {
    case CycleStatus.noPeriods:
      return null;
    case CycleStatus.hormonalContraception:
      final day = state.periodDay;
      return day == null ? null : 'Bleed day $day';
    case CycleStatus.regular:
    case CycleStatus.irregular:
      final day = state.periodDay;
      if (day != null) return 'Period day $day';
      final late = state.lateDays;
      if (late != null && late > 0) {
        return late == 1
            ? 'Period is 1 day later than usual'
            : 'Period is $late days later than usual';
      }
      final cycleDay = state.cycleDay;
      if (cycleDay == null) return null;
      final from = state.expectedFrom;
      final to = state.expectedTo;
      return from == null || to == null
          ? 'Cycle day $cycleDay'
          : 'Cycle day $cycleDay · period expected '
                '${cycleDateRange(from, to)}';
  }
}

/// The note under the recovery drivers in the second half of the cycle, or
/// null. It explains the expected shift; the score is not changed.
String? cycleRecoveryNote(CycleAnswer answer) {
  if (!answer.trackingEnabled) return null;
  final state = answer.state;
  final confident =
      state.confidence == CycleConfidence.medium ||
      state.confidence == CycleConfidence.high;
  if (state.phase != CyclePhase.secondHalf || !confident) return null;
  return 'Second half of your cycle: resting heart rate often runs a little '
      "higher and HRV a little lower. That's expected.";
}

/// The note on the weight trend around a period, or null.
String? cycleWeightNote(CycleAnswer answer) {
  if (!answer.trackingEnabled || !answer.state.weightWaterWindow) return null;
  return 'Weight often runs higher around a period (water). Compare with the '
      'same point last cycle.';
}

/// The long-gap card's sentence, or null.
String? cycleLongGapMessage(CycleAnswer answer) {
  if (!answer.trackingEnabled || !answer.state.noPeriodLong) return null;
  final months = answer.status == CycleStatus.irregular ? 6 : 3;
  return "No period logged for $months months. If that's not expected for "
      "you, it's worth talking to a doctor.";
}
