import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/cycle/cycle_labels.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// How far back a day can be logged or changed.
const cycleEditableDays = 365;

/// Logs or changes one day: bleeding, cramps and whether it began a period.
/// Completes with the answer the server returned after saving, or null when
/// she leaves without saving.
///
/// [existing] fills the sheet with what is stored for [date]. With
/// [startsPeriod] a new day opens as the first day of a period. With
/// [canChangeDate] the date can be moved.
Future<CycleAnswer?> showCycleDaySheet(
  BuildContext context, {
  required CycleRepository repository,
  required DateTime date,
  CycleDay? existing,
  bool startsPeriod = false,
  bool canChangeDate = false,
  DateTime Function() now = DateTime.now,
}) => showTracendSheet<CycleAnswer>(
  context,
  title: startsPeriod ? 'Log a period' : 'Log a day',
  scrollable: false,
  padding: EdgeInsets.zero,
  builder: (_) => _CycleDaySheet(
    repository: repository,
    date: date,
    existing: existing,
    startsPeriod: startsPeriod,
    canChangeDate: canChangeDate,
    now: now,
  ),
);

class _CycleDaySheet extends StatefulWidget {
  const _CycleDaySheet({
    required this.repository,
    required this.date,
    required this.existing,
    required this.startsPeriod,
    required this.canChangeDate,
    required this.now,
  });

  final CycleRepository repository;
  final DateTime date;
  final CycleDay? existing;
  final bool startsPeriod;
  final bool canChangeDate;
  final DateTime Function() now;

  @override
  State<_CycleDaySheet> createState() => _CycleDaySheetState();
}

class _CycleDaySheetState extends State<_CycleDaySheet> {
  late DateTime _date = DateTime(
    widget.date.year,
    widget.date.month,
    widget.date.day,
  );
  late PeriodFlow? _flow =
      widget.existing?.flow ??
      (widget.startsPeriod ? PeriodFlow.unspecified : null);
  late CycleCramps? _cramps = widget.existing?.cramps;
  late bool _isStart = widget.existing?.isStart ?? widget.startsPeriod;
  bool _saving = false;
  String? _failure;

  bool get _canStart => _flow != null && _flow!.isPeriodDay;

  Future<void> _pickDate() async {
    final today = widget.now();
    final last = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(last) ? last : _date,
      firstDate: last.subtract(const Duration(days: cycleEditableDays)),
      lastDate: last,
      helpText: 'Which day?',
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _failure = null;
      });
    }
  }

  void _choose(PeriodFlow? flow) => setState(() {
    _flow = flow;
    _failure = null;
    if (flow == null) _cramps = null;
    if (flow == null || !flow.isPeriodDay) _isStart = false;
  });

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final answer = await widget.repository.logDay(
        date: _date,
        flow: _flow,
        cramps: _flow == null ? null : _cramps,
        isStart: _canStart && _isStart,
      );
      if (mounted) Navigator.of(context).pop(answer);
    } catch (error) {
      logNonCritical(error, 'cycle day not saved');
      if (mounted) {
        setState(() {
          _saving = false;
          _failure = cycleFailureMessage(
            error,
            fallback: 'Not saved. Try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              TracendSpacing.gutter,
              TracendSpacing.xs,
              TracendSpacing.gutter,
              TracendSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canChangeDate)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(CupertinoIcons.calendar, size: 18),
                    label: Text(dayAndDate(_date, now: widget.now())),
                  )
                else
                  Text(
                    dayAndDate(_date, now: widget.now()),
                    style: textTheme.titleMedium,
                  ),
                const SizedBox(height: TracendSpacing.md),
                ChoiceGroup(
                  title: 'Bleeding',
                  options: [
                    (
                      label: 'No period',
                      selected: _flow == null,
                      onTap: () => _choose(null),
                    ),
                    for (final flow in const [
                      PeriodFlow.spotting,
                      PeriodFlow.light,
                      PeriodFlow.medium,
                      PeriodFlow.heavy,
                      PeriodFlow.unspecified,
                    ])
                      (
                        label: flow == PeriodFlow.unspecified
                            ? 'Period, flow not noted'
                            : periodFlowLabel(flow),
                        selected: _flow == flow,
                        onTap: () => _choose(flow),
                      ),
                  ],
                ),
                if (_flow != null) ...[
                  const SizedBox(height: TracendSpacing.lg),
                  ChoiceGroup(
                    title: 'Cramps',
                    options: [
                      for (final cramps in CycleCramps.values)
                        (
                          label: cycleCrampsLabel(cramps),
                          selected: _cramps == cramps,
                          onTap: () => setState(() {
                            _cramps = cramps;
                            _failure = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_canStart) ...[
                  const SizedBox(height: TracendSpacing.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(TracendRadii.card),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: TracendSpacing.md,
                      ),
                      title: Text(
                        'First day of this period',
                        style: textTheme.titleSmall,
                      ),
                      value: _isStart,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _isStart = value),
                    ),
                  ),
                ],
                if (_failure case final failure?) ...[
                  const SizedBox(height: TracendSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failure,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.stateDanger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderHairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TracendSpacing.gutter,
              TracendSpacing.sm,
              TracendSpacing.gutter,
              0,
            ),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ),
      ],
    );
  }
}
