import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/cycle/cycle_health.dart';
import 'package:tracend/features/cycle/cycle_labels.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/cycle/widgets/cycle_consent_sheet.dart';
import 'package:tracend/features/cycle/widgets/cycle_day_sheet.dart';
import 'package:tracend/features/cycle/widgets/cycle_inputs.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/plan_changes.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Account › Cycle: the one row that opens [CycleSettingsScreen]. It is shown
/// to everyone; tracking is off until she turns it on.
class CycleSettings extends StatefulWidget {
  const CycleSettings({
    required this.repository,
    this.health,
    this.changes,
    super.key,
  });

  final CycleRepository repository;
  final CycleHealthSync? health;
  final CycleChanges? changes;

  @override
  State<CycleSettings> createState() => _CycleSettingsState();
}

class _CycleSettingsState extends State<CycleSettings> {
  CycleAnswer? _answer;
  bool _unreadable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final answer = await widget.repository.load();
      if (mounted) {
        setState(() {
          _answer = answer;
          _unreadable = false;
        });
      }
    } catch (error) {
      logNonCritical(error, 'cycle not read');
      if (mounted) setState(() => _unreadable = true);
    }
  }

  String get _subtitle {
    final answer = _answer;
    if (_unreadable) return 'Could not be read · open to try again';
    if (answer == null) return 'Checking…';
    final status = answer.status;
    if (!answer.trackingEnabled || status == null) {
      return 'Off · optional, for periods and your cycle';
    }
    return 'On · ${cycleStatusShort(status)}';
  }

  Future<void> _open() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => CycleSettingsScreen(
          repository: widget.repository,
          health: widget.health,
          changes: widget.changes,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => TracendGroupedList(
    children: [
      TracendListRow(
        title: 'Cycle tracking',
        subtitle: _subtitle,
        leading: const TracendRowIcon(icon: CupertinoIcons.calendar),
        onTap: _open,
      ),
    ],
  );
}

/// Turns cycle tracking on or off, says how her cycle works, and lists the
/// recent cycles with a way to change a day. Every change is saved on the
/// server at once; nothing is kept on the phone.
class CycleSettingsScreen extends StatefulWidget {
  const CycleSettingsScreen({
    required this.repository,
    this.health,
    this.changes,
    this.now = DateTime.now,
    super.key,
  });

  final CycleRepository repository;

  /// Reads Apple Health's period days; null hides that switch.
  final CycleHealthSync? health;
  final CycleChanges? changes;
  final DateTime Function() now;

  @override
  State<CycleSettingsScreen> createState() => _CycleSettingsScreenState();
}

class _CycleSettingsScreenState extends State<CycleSettingsScreen> {
  CycleAnswer? _answer;
  bool _loadFailed = false;
  bool _busy = false;

  /// A sheet (the agreement, the cycle type, the length, a day) is open or
  /// about to open, so no second one opens on a double tap.
  bool _asking = false;
  String? _message;

  bool get _locked => _busy || _asking;

  Future<T?> _ask<T>(Future<T?> Function() sheet) async {
    if (_locked) return null;
    setState(() => _asking = true);
    try {
      return await sheet();
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final answer = await widget.repository.load();
      if (mounted) setState(() => _answer = answer);
    } catch (error) {
      logNonCritical(error, 'cycle not read');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// Runs one change, shows what the server returned and tells Today and
  /// Progress. A failed change leaves the screen as it was and says so.
  Future<bool> _run(
    Future<CycleAnswer> Function() change, {
    String failure = 'Not saved. Check your connection and try again.',
  }) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final answer = await change();
      if (!mounted) return true;
      setState(() => _answer = answer);
      unawaited(TracendHaptics.light());
      widget.changes?.announce();
      return true;
    } catch (error) {
      logNonCritical(error, 'cycle change not saved');
      if (mounted) {
        setState(
          () => _message = error is _AppleHealthClosed
              ? 'Apple Health could not be opened.'
              : cycleFailureMessage(error, fallback: failure),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CycleAnswer> _save(
    CycleAnswer current, {
    bool? tracking,
    CycleStatus? status,
    Object? typical = _keep,
    bool? appleHealth,
  }) => widget.repository.saveSettings(
    trackingEnabled: tracking ?? current.trackingEnabled,
    status: status ?? current.status,
    typicalCycleDays: identical(typical, _keep)
        ? current.typicalCycleDays
        : typical as int?,
    appleHealthEnabled: appleHealth ?? current.appleHealthEnabled,
  );

  Future<void> _setTracking(CycleAnswer current, bool on) async {
    if (_locked) return;
    if (!on) {
      await _run(() => _save(current, tracking: false, appleHealth: false));
      return;
    }
    final status = await _ask<CycleStatus>(() async {
      if (!await ensureCycleConsent(context, widget.repository) || !mounted) {
        return null;
      }
      return current.status ?? await showCycleStatusSheet(context);
    });
    if (status == null || !mounted) return;
    await _run(() => _save(current, tracking: true, status: status));
  }

  Future<void> _chooseStatus(CycleAnswer current) async {
    final status = await _ask(
      () => showCycleStatusSheet(context, selected: current.status),
    );
    if (status == null || status == current.status || !mounted) return;
    await _run(() => _save(current, status: status));
  }

  Future<void> _chooseLength(CycleAnswer current) async {
    final pick = await _ask(
      () => showCycleLengthSheet(context, current: current.typicalCycleDays),
    );
    if (pick == null || pick.days == current.typicalCycleDays || !mounted) {
      return;
    }
    await _run(() => _save(current, typical: pick.days));
  }

  /// Saves the switch first: iOS's permission sheet is shown only once the
  /// database has accepted it, so a refused save never asks. If Apple Health
  /// cannot be asked or read, the switch is saved off again.
  Future<void> _setAppleHealth(CycleAnswer current, bool on) async {
    final health = widget.health;
    if (health == null || _locked) return;
    if (!on) {
      await _run(() => _save(current, appleHealth: false));
      return;
    }
    await _run(() async {
      final saved = await _save(current, appleHealth: true);
      try {
        if (!await health.requestAccess()) throw const _AppleHealthClosed();
        await health.backfill();
      } catch (error) {
        // The switch is not left on for days that were never read.
        logNonCritical(error, 'cycle days not read from Apple Health');
        await _save(saved, appleHealth: false);
        rethrow;
      }
      return widget.repository.load();
    }, failure: 'Periods could not be read from Apple Health. Try again.');
  }

  Future<void> _editDay(CycleAnswer current, DateTime date) async {
    final answer = await _ask(
      () => showCycleDaySheet(
        context,
        repository: widget.repository,
        date: date,
        answer: current,
        canChangeDate: true,
        now: widget.now,
      ),
    );
    if (answer == null || !mounted) return;
    setState(() => _answer = answer);
    widget.changes?.announce();
  }

  Future<void> _delete() async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete my cycle data?',
      message:
          "This removes every period day and cycle answer. It can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final deleted = await _run(
      widget.repository.deleteAll,
      failure: 'Your cycle data was not deleted. Try again.',
    );
    if (deleted && mounted) {
      TracendToast.show(context, 'Cycle data deleted');
    }
  }

  static const _keep = Object();

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    final answer = _answer;
    return Scaffold(
      appBar: AppBar(title: const Text('Cycle tracking')),
      body: SafeArea(
        top: false,
        child: answer == null
            ? _loadFailed
                  ? AccountDetailMessage(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: 'Your cycle settings could not load',
                      detail:
                          'Nothing was changed. Check the connection and try '
                          'again.',
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    )
                  : const Center(
                      child: TracendLoader(
                        semanticLabel: 'Loading your cycle settings',
                      ),
                    )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  TracendSpacing.xs,
                  gutter,
                  TracendSpacing.xxl,
                ),
                children: _content(context, answer),
              ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, CycleAnswer answer) {
    final colors = context.tracendColors;
    final status = answer.status;
    final tracking = answer.trackingEnabled && status != null;
    final cycles = answer.cycles.reversed.take(6).toList();
    final hasData =
        answer.trackingEnabled ||
        status != null ||
        answer.recentDays.isNotEmpty ||
        answer.cycles.isNotEmpty;
    return [
      TracendGroupedList(
        children: [
          _SwitchRow(
            title: 'Track my cycle',
            subtitle: 'Period days and how your cycle works',
            value: tracking,
            onChanged: _locked ? null : (on) => _setTracking(answer, on),
          ),
          if (tracking) ...[
            TracendListRow(
              title: 'Cycle',
              subtitle: cycleStatusLabel(status),
              onTap: _locked ? null : () => _chooseStatus(answer),
            ),
            if (status.hasCycleDays)
              TracendListRow(
                title: 'Typical cycle length',
                subtitle: answer.typicalCycleDays == null
                    ? 'Not set'
                    : '${answer.typicalCycleDays} days',
                onTap: _locked ? null : () => _chooseLength(answer),
              ),
            if (widget.health != null)
              _SwitchRow(
                title: 'Read periods from Apple Health',
                subtitle:
                    'Period days in Apple Health join the ones you log. Days '
                    'you log yourself always win.',
                value: answer.appleHealthEnabled,
                onChanged: _locked ? null : (on) => _setAppleHealth(answer, on),
              ),
          ],
        ],
      ),
      if (_message case final message?)
        Semantics(
          liveRegion: true,
          child: AccountFootnote(message, color: colors.stateDanger),
        ),
      const AccountFootnote(
        'Optional. It helps read your recovery, weight and energy fairly. It '
        'stays on Tracend’s server, is never used for ads or shared, and Coach '
        'uses it only after you accept an AI notice that names it.',
      ),
      if (tracking && cycles.isNotEmpty) ...[
        const SectionLabel('Recent cycles'),
        TracendGroupedList(
          children: [
            for (final cycle in cycles)
              TracendListRow(
                title:
                    'Started ${shortDate(cycle.startDate, now: widget.now())}',
                subtitle: _cycleSubtitle(cycle),
                onTap: _locked ? null : () => _editDay(answer, cycle.startDate),
              ),
          ],
        ),
      ],
      if (tracking) ...[
        const SizedBox(height: TracendSpacing.sm),
        TracendGroupedList(
          children: [
            TracendListRow(
              title: 'Log or change a day',
              subtitle: 'A period day, spotting or cramps',
              leading: const TracendRowIcon(icon: CupertinoIcons.pencil),
              onTap: _locked ? null : () => _editDay(answer, widget.now()),
            ),
          ],
        ),
      ],
      if (hasData) ...[
        const SectionLabel('Privacy'),
        TracendGroupedList(
          children: [
            TracendListRow(
              title: 'Delete my cycle data',
              subtitle: 'Every period day and cycle answer',
              leading: TracendRowIcon(
                icon: CupertinoIcons.delete,
                color: colors.stateDanger,
              ),
              onTap: _locked ? null : _delete,
            ),
          ],
        ),
      ],
    ];
  }

  String _cycleSubtitle(CycleRecord cycle) {
    final length = cycle.lengthDays;
    if (length == null) return 'Current cycle';
    return cycle.used
        ? '$length days'
        : '$length days · left out of your usual length';
  }
}

/// A grouped-list row with a trailing switch. VoiceOver reads the title,
/// detail and switch state as one element.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: TracendListRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    ),
  );
}

/// Apple Health cannot be asked for menstrual flow on this phone.
class _AppleHealthClosed implements Exception {
  const _AppleHealthClosed();
}
