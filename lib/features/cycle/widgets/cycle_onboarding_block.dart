import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/cycle/widgets/cycle_consent_sheet.dart';
import 'package:tracend/features/cycle/widgets/cycle_day_sheet.dart';
import 'package:tracend/features/cycle/widgets/cycle_inputs.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';

enum _Stage { loading, hidden, ask, status, details, done, skipped }

/// The optional "Your cycle" block at the foot of About you, for an athlete
/// whose sex is female or not given. Every answer is saved the moment it is
/// given, through the cycle RPCs; none of it joins the setup draft, and
/// nothing here can stop her carrying on with the step.
///
/// It stays out of the way when it cannot help: it shows nothing while the
/// cycle is read, when the read fails, and when she already has cycle
/// settings.
class CycleOnboardingBlock extends StatefulWidget {
  const CycleOnboardingBlock({
    required this.repository,
    this.now = DateTime.now,
    super.key,
  });

  final CycleRepository repository;
  final DateTime Function() now;

  @override
  State<CycleOnboardingBlock> createState() => _CycleOnboardingBlockState();
}

class _CycleOnboardingBlockState extends State<CycleOnboardingBlock> {
  _Stage _stage = _Stage.loading;
  CycleStatus? _status;
  DateTime? _lastPeriod;
  bool _lastPeriodUnsure = false;
  int _length = cycleLengthDefault;
  bool _lengthUnsure = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    _Stage stage;
    try {
      final answer = await widget.repository.load();
      final exists = answer.trackingEnabled || answer.status != null;
      stage = exists ? _Stage.hidden : _Stage.ask;
    } catch (error) {
      logNonCritical(error, 'cycle not read');
      stage = _Stage.hidden;
    }
    if (mounted) setState(() => _stage = stage);
  }

  Future<void> _yes() async {
    if (_busy) return;
    setState(() => _error = null);
    if (!await ensureCycleConsent(context, widget.repository) || !mounted) {
      return;
    }
    setState(() => _stage = _Stage.status);
  }

  Future<void> _chooseStatus(CycleStatus status) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveSettings(
        trackingEnabled: true,
        status: status,
        typicalCycleDays: null,
        appleHealthEnabled: false,
      );
      if (mounted) {
        setState(() {
          _status = status;
          _stage = status.hasCycleDays ? _Stage.details : _Stage.done;
        });
      }
    } catch (error) {
      logNonCritical(error, 'cycle status not saved');
      if (mounted) {
        setState(
          () => _error = cycleFailureMessage(
            error,
            fallback: 'Not saved. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final today = widget.now();
    final last = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastPeriod ?? last,
      firstDate: last.subtract(const Duration(days: cycleEditableDays)),
      lastDate: last,
      helpText: 'When did your last period start?',
    );
    if (picked != null && mounted) {
      setState(() {
        _lastPeriod = DateTime(picked.year, picked.month, picked.day);
        _lastPeriodUnsure = false;
      });
    }
  }

  Future<void> _saveDetails() async {
    final status = _status;
    if (_busy || status == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveSettings(
        trackingEnabled: true,
        status: status,
        typicalCycleDays: _lengthUnsure ? null : _length,
        appleHealthEnabled: false,
      );
      final lastPeriod = _lastPeriod;
      if (lastPeriod != null && !_lastPeriodUnsure) {
        await widget.repository.logDay(
          date: lastPeriod,
          flow: PeriodFlow.unspecified,
          isStart: true,
        );
      }
      if (mounted) setState(() => _stage = _Stage.done);
    } catch (error) {
      logNonCritical(error, 'cycle answers not saved');
      if (mounted) {
        setState(
          () => _error = cycleFailureMessage(
            error,
            fallback: 'Not saved. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.loading || _stage == _Stage.hidden) {
      return const SizedBox.shrink();
    }
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('cycle-onboarding'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: TracendSpacing.lg,
            bottom: TracendSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text('Your cycle', style: textTheme.titleMedium),
          ),
        ),
        ..._body(context),
        if (_error case final error?) ...[
          const SizedBox(height: TracendSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _body(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    switch (_stage) {
      case _Stage.loading:
      case _Stage.hidden:
        return const [];
      case _Stage.ask:
        return [
          Text(
            'Take my menstrual cycle into account?',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            'Optional. It helps read your recovery, weight and energy fairly. '
            'You can change this any time in Account.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('cycle-onboarding-yes'),
                  onPressed: _busy ? null : _yes,
                  child: const Text('Yes'),
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('cycle-onboarding-not-now'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _stage = _Stage.skipped),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        ];
      case _Stage.status:
        return [CycleStatusChoices(selected: _status, onChosen: _chooseStatus)];
      case _Stage.details:
        return _details(context);
      case _Stage.done:
        return [
          Text(
            'Cycle tracking is on. You can change it any time in Account.',
            style: textTheme.bodyMedium,
          ),
        ];
      case _Stage.skipped:
        return [
          Text(
            'You can turn on cycle tracking any time in Account.',
            style: textTheme.bodyMedium,
          ),
        ];
    }
  }

  List<Widget> _details(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return [
      Text('When did your last period start?', style: textTheme.titleSmall),
      const SizedBox(height: TracendSpacing.xs),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('cycle-onboarding-date'),
            onPressed: _busy ? null : _pickDate,
            icon: const Icon(CupertinoIcons.calendar, size: 18),
            label: Text(
              _lastPeriod == null || _lastPeriodUnsure
                  ? 'Choose a date'
                  : dayAndDate(_lastPeriod!, now: widget.now()),
            ),
          ),
          _NotSureChip(
            key: const ValueKey('cycle-onboarding-date-unsure'),
            selected: _lastPeriodUnsure,
            onTap: _busy
                ? null
                : () => setState(() {
                    _lastPeriodUnsure = !_lastPeriodUnsure;
                    if (_lastPeriodUnsure) _lastPeriod = null;
                  }),
          ),
        ],
      ),
      const SizedBox(height: TracendSpacing.md),
      Text('How long is your cycle usually?', style: textTheme.titleSmall),
      const SizedBox(height: TracendSpacing.xxs),
      Text(
        'From the first day of one period to the first day of the next.',
        style: textTheme.bodySmall?.copyWith(
          color: context.tracendColors.textSecondary,
        ),
      ),
      if (!_lengthUnsure)
        CycleLengthStepper(
          days: _length,
          onChanged: (days) => setState(() => _length = days),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: _NotSureChip(
          key: const ValueKey('cycle-onboarding-length-unsure'),
          selected: _lengthUnsure,
          onTap: _busy
              ? null
              : () => setState(() => _lengthUnsure = !_lengthUnsure),
        ),
      ),
      const SizedBox(height: TracendSpacing.md),
      FilledButton(
        key: const ValueKey('cycle-onboarding-save'),
        onPressed: _busy ? null : _saveDetails,
        child: Text(_busy ? 'Saving…' : 'Save'),
      ),
    ];
  }
}

class _NotSureChip extends StatelessWidget {
  const _NotSureChip({required this.selected, required this.onTap, super.key});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: const Text('Not sure'),
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap!(),
  );
}
