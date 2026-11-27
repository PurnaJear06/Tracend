import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/cycle/cycle_labels.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/shared/diagnostics.dart';

/// What the daily check-in needs to ask "Period today?": where a tap is saved,
/// and what the cycle answer held when the sheet opened. The answer is saved
/// by the control itself, apart from the check-in, so it never joins the
/// check-in's payload, its queue or its unsaved-input guard.
class CheckInPeriod {
  const CheckInPeriod({
    required this.repository,
    required this.answer,
    this.onChanged,
  });

  final CycleRepository repository;
  final CycleAnswer answer;

  /// Told the new cycle answer after each saved tap, so Today's cycle line
  /// follows.
  final ValueChanged<CycleAnswer>? onChanged;
}

/// Whether the check-in asks about a period: tracking is on and she has
/// periods to log.
bool asksAboutPeriod(CycleAnswer answer) =>
    answer.trackingEnabled &&
    answer.status != null &&
    answer.status != CycleStatus.noPeriods;

enum _Status { idle, saving, saved, failed }

typedef _Answer = ({bool? yes, PeriodFlow? flow, CycleCramps? cramps});

/// "Period today?" for the daily check-in: No or Yes, and for Yes the flow and
/// the cramps. Every tap is saved on its own (`log_cycle_day_v1`) and says
/// "Saved" or "Not saved. Try again." beside the question.
class PeriodTodayControl extends StatefulWidget {
  const PeriodTodayControl({
    required this.period,
    required this.date,
    super.key,
  });

  final CheckInPeriod period;

  /// The day the check-in is for.
  final DateTime date;

  @override
  State<PeriodTodayControl> createState() => _PeriodTodayControlState();
}

class _PeriodTodayControlState extends State<PeriodTodayControl> {
  static const _flows = [
    PeriodFlow.spotting,
    PeriodFlow.light,
    PeriodFlow.medium,
    PeriodFlow.heavy,
  ];

  late final CycleDay? _stored = widget.period.answer.dayOn(widget.date);
  late _Answer _shown = _initial();
  late _Answer _saved = _shown;
  _Status _status = _Status.idle;
  Future<void> _chain = Future<void>.value();
  int _pending = 0;

  _Answer _initial() {
    final day = _stored;
    if (day == null) return (yes: null, flow: null, cramps: null);
    // A day with no level ("period, flow not noted") shows as Yes with the
    // level still to choose: the control never sends it back as it was.
    final flow = day.flow == PeriodFlow.unspecified ? null : day.flow;
    return (
      yes: day.flow != null,
      flow: flow,
      cramps: flow == null ? null : day.cramps,
    );
  }

  void _no() {
    setState(() => _shown = (yes: false, flow: null, cramps: null));
    _save();
  }

  void _yes() {
    if (_shown.yes ?? false) return;
    // Nothing is stored for "Yes" until she says how heavy it is.
    setState(() {
      _shown = (yes: true, flow: _shown.flow, cramps: null);
      _status = _Status.idle;
    });
  }

  void _flow(PeriodFlow flow) {
    setState(() => _shown = (yes: true, flow: flow, cramps: _shown.cramps));
    _save();
  }

  void _cramps(CycleCramps cramps) {
    setState(() => _shown = (yes: true, flow: _shown.flow, cramps: cramps));
    _save();
  }

  void _save() {
    final answer = _shown;
    final repository = widget.period.repository;
    final date = widget.date;
    _pending++;
    setState(() => _status = _Status.saving);
    _chain = _chain.then((_) async {
      CycleAnswer? stored;
      try {
        stored = await repository.logDay(
          date: date,
          flow: answer.flow,
          cramps: answer.cramps,
          isStart:
              (_stored?.isStart ?? false) &&
              (answer.flow?.isPeriodDay ?? false) &&
              answer.flow != PeriodFlow.unspecified,
        );
      } catch (error) {
        logNonCritical(error, 'period not saved');
      }
      _pending--;
      if (stored != null) {
        _saved = answer;
        widget.period.onChanged?.call(stored);
      }
      if (!mounted) return;
      setState(() {
        if (_pending > 0) return;
        _status = stored == null ? _Status.failed : _Status.saved;
        // What is shown is only what is stored.
        if (stored == null) _shown = _saved;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final yes = _shown.yes;
    final flow = _shown.flow;
    final message = switch (_status) {
      _Status.saving => 'Saving…',
      _Status.saved => 'Saved',
      _Status.failed => 'Not saved. Try again.',
      _Status.idle =>
        (yes ?? false) && flow == null
            ? 'Choose how heavy it is to save it.'
            : null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceGroup(
          title: 'Period today?',
          options: [
            (label: 'No', selected: yes == false, onTap: _no),
            (label: 'Yes', selected: yes == true, onTap: _yes),
          ],
        ),
        if (yes ?? false) ...[
          const SizedBox(height: TracendSpacing.md),
          ChoiceGroup(
            title: 'Flow',
            options: [
              for (final option in _flows)
                (
                  label: periodFlowLabel(option),
                  selected: flow == option,
                  onTap: () => _flow(option),
                ),
            ],
          ),
          if (flow != null) ...[
            const SizedBox(height: TracendSpacing.md),
            ChoiceGroup(
              title: 'Cramps',
              options: [
                for (final option in CycleCramps.values)
                  (
                    label: cycleCrampsLabel(option),
                    selected: _shown.cramps == option,
                    onTap: () => _cramps(option),
                  ),
              ],
            ),
          ],
        ],
        if (message != null) ...[
          const SizedBox(height: TracendSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: _status == _Status.failed
                    ? colors.stateDanger
                    : colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
