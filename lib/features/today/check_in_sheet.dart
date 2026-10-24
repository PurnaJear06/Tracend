import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// What a saved check-in left to say.
@immutable
class CheckInSaved {
  const CheckInSaved({
    required this.delivered,
    this.referralRoute,
    this.pending,
  });

  /// Tracend has the check-in. False when it waits on this phone, or when the
  /// sheet closed before the send settled ([pending]).
  final bool delivered;

  /// The safety route the pain answers give (`urgent`, `clinician_today` or
  /// `clinician`), worked out on the phone by the same rules as the server's
  /// so that a red flag is answered at once even when nothing was sent.
  final String? referralRoute;

  /// Set when the sheet closed at once, for a referral, while the check-in was
  /// still on its way: completes with whether Tracend has it. The referral
  /// never waits for the network.
  final Future<bool>? pending;
}

/// Opens the daily check-in sheet. [sender] replaces the
/// `save_daily_check_in` RPC (tests inject a recording fake); without it the
/// sheet calls Supabase when the environment is configured.
/// Resolves with what was saved when the check-in was saved, delivered or
/// queued on this device, and null when the sheet was dismissed.
///
/// [localDate] (`YYYY-MM-DD`) is the athlete's own today as the server counts
/// it, when it is known: the check-in is saved, and queued, under that day, so
/// the rules that read "today's check-in" find it. Without it the phone's date
/// is used.
///
/// [jointStates] are the areas already held, limited or on watch: the sheet
/// asks how each is today.
Future<CheckInSaved?> showCheckInSheet(
  BuildContext context,
  AppEnvironment environment, {
  CheckInSend? sender,
  String? localDate,
  List<JointState> jointStates = const [],
}) => showTracendSheet<CheckInSaved>(
  context,
  title: 'Daily check-in',
  scrollable: false,
  padding: EdgeInsets.zero,
  builder: (_) => _CheckInSheet(
    environment: environment,
    sender: sender,
    localDate: localDate,
    jointStates: jointStates,
  ),
);

/// One labelled five-point question. The labels run from the first stored
/// value to the last: `labels[0]` is stored as 1 and `labels[4]` as 5.
@immutable
class CheckInScale {
  const CheckInScale({
    required this.key,
    required this.title,
    required this.labels,
    this.reversed = false,
  });

  /// The payload key (`save_daily_check_in`).
  final String key;
  final String title;

  /// Option labels in the order they are shown, worst to best.
  final List<String> labels;

  /// True when the shown order runs against the stored values: the first
  /// option is stored as 5 and the last as 1 (soreness, where 5 is very
  /// sore and "Great" means not sore).
  final bool reversed;

  /// The stored 1–5 value of the option at [index] in the shown order.
  int valueAt(int index) => reversed ? 5 - index : index + 1;

  /// The label for a stored 1–5 [value].
  String labelFor(int value) => labels[reversed ? 5 - value : value - 1];
}

/// The five scales, stored exactly as before (1–5, 3 is the middle).
const checkInScales = [
  CheckInScale(
    key: 'sleep_quality',
    title: 'Sleep quality',
    labels: ['Very poor', 'Poor', 'OK', 'Good', 'Great'],
  ),
  CheckInScale(
    key: 'energy',
    title: 'Energy',
    labels: ['Very low', 'Low', 'OK', 'Good', 'Great'],
  ),
  CheckInScale(
    key: 'soreness',
    title: 'Soreness',
    labels: ['Very sore', 'Sore', 'A bit sore', 'Good', 'Great, not sore'],
    reversed: true,
  ),
  CheckInScale(
    key: 'hunger',
    title: 'Hunger',
    labels: [
      'Not hungry',
      'A little hungry',
      'Normal',
      'Hungry',
      'Very hungry',
    ],
  ),
  CheckInScale(
    key: 'mood',
    title: 'Mood',
    labels: ['Very low', 'Low', 'OK', 'Good', 'Great'],
  ),
];

/// How the send of a saved check-in ended.
enum _Sent { delivered, waiting, painRefused }

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({
    required this.environment,
    required this.sender,
    required this.localDate,
    required this.jointStates,
  });

  final AppEnvironment environment;
  final CheckInSend? sender;
  final String? localDate;
  final List<JointState> jointStates;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  static const _noteLimit = 1000;

  /// The counter appears once the note is within this many characters of
  /// the limit.
  static const _counterFrom = 900;

  final _values = <String, int>{
    for (final scale in checkInScales) scale.key: 3,
  };

  /// 0 is no pain; 1–10 is how strong it is.
  int _pain = 0;
  bool _painReported = false;
  bool _painMissing = false;

  /// Where the pain is, when it hurts, and the red-flag answer. The flags
  /// are the codes ticked; [_noneOfThese] is the answer "None of these".
  PainArea? _area;
  String? _pattern;
  final Set<String> _flags = {};
  bool _noneOfThese = false;
  bool _areaMissing = false;
  bool _flagsMissing = false;

  /// How each area that was already held, limited or on watch is today.
  final Map<PainArea, _FollowUp> _followUps = {};
  final Set<PainArea> _followMissing = {};

  final _note = TextEditingController();
  bool _available = true;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The follow-ups that will be sent: an area the athlete reports again as
  /// today's pain is answered there, with its own red-flag question.
  Map<PainArea, _FollowUp> get _sentFollowUps => {
    for (final entry in _followUps.entries)
      if (entry.value.answered && !(_painReported && _area == entry.key))
        entry.key: entry.value,
  };

  /// Whether the pain answers are complete; sets the messages when not.
  bool _painAnswersComplete() {
    final missingStrength = _painReported && _pain == 0;
    final missingArea = _painReported && _area == null;
    final missingFlags = _painReported && !_noneOfThese && _flags.isEmpty;
    final missingFollow = {
      for (final entry in _followUps.entries)
        if (entry.value.needsStrength &&
            entry.value.severity == null &&
            !(_painReported && _area == entry.key))
          entry.key,
    };
    if (!missingStrength &&
        !missingArea &&
        !missingFlags &&
        missingFollow.isEmpty) {
      return true;
    }
    unawaited(TracendHaptics.warning());
    setState(() {
      _painMissing = missingStrength;
      _areaMissing = missingArea;
      _flagsMissing = missingFlags;
      _followMissing
        ..clear()
        ..addAll(missingFollow);
    });
    return false;
  }

  /// The pain answers as `save_daily_check_in` takes them. Nothing is sent
  /// for a check-in with no pain and no follow-up, which a build that did not
  /// ask the questions also sends.
  Map<String, dynamic> _painPayload() {
    final follow = _sentFollowUps;
    return {
      if (_painReported && _area != null) ...{
        'pain_area': _area!.name,
        'pain_pattern': ?_pattern,
        'pain_red_flags': (_flags.toList()..sort()),
        // An area a doctor or physio cleared, reported again as today's pain,
        // is one report: it carries the clearance with it.
        if (_followUps[_area]?.cleared ?? false)
          'pain_cleared_by_clinician': true,
      },
      if (follow.isNotEmpty)
        'pain_followups': [
          for (final entry in follow.entries)
            {
              'area': entry.key.name,
              'severity': entry.value.reportedSeverity,
              'cleared_by_clinician': entry.value.cleared,
            },
        ],
    };
  }

  /// The strictest route the pain answers give, by the server's own rules.
  String? _localRoute() {
    PainOutcome? strictest;
    void consider(PainOutcome outcome) {
      if (!outcome.routesOut) return;
      if (strictest == null || outcome.index < strictest!.index) {
        strictest = outcome;
      }
    }

    if (_painReported && _area != null) {
      consider(painOutcome(_pain, _flags.toList()));
    }
    for (final entry in _sentFollowUps.entries) {
      consider(painOutcome(entry.value.reportedSeverity, null));
    }
    return strictest?.route;
  }

  /// How long the sheet waits for the server before it keeps the check-in on
  /// the phone and closes.
  static const _sendWait = Duration(seconds: 8);

  Future<void> _save() async {
    if (!_painAnswersComplete()) return;
    setState(() => _saving = true);
    try {
      await _saveNow();
    } on Object catch (error) {
      // Whatever went wrong, the sheet is not left saving for good.
      debugPrint('Non-critical error: check-in not saved: $error');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNow() async {
    final now = DateTime.now();
    final localDate =
        widget.localDate ?? now.toIso8601String().substring(0, 10);
    final timezone = now.timeZoneName;
    final payload = {
      for (final scale in checkInScales) scale.key: _values[scale.key]!,
      'pain_severity': _pain,
      ..._painPayload(),
      'available_to_train': _available,
      'note': _note.text.trim(),
    };
    final withPain = payload.keys.any(_isPainKey);
    final route = _localRoute();
    // The envelope is queued before the RPC so the check-in survives a lost
    // connection; Today retries it on the next launch via CheckInQueue.
    final sending = _persistAndSend(payload, localDate, timezone);
    if (route != null) {
      // A referral is shown at once, from the phone's own rules: it never
      // waits for the network, and closing the sheet cannot lose it.
      Navigator.pop(
        context,
        CheckInSaved(
          delivered: false,
          referralRoute: route,
          pending: sending.then((result) => result == _Sent.delivered),
        ),
      );
      return;
    }
    var result = _Sent.waiting;
    try {
      result = await sending.timeout(_sendWait);
    } on TimeoutException {
      // The send goes on; the envelope waits on the phone meanwhile.
    }
    if (!mounted) return;
    if (result == _Sent.delivered) {
      unawaited(TracendHaptics.success());
      TracendToast.show(context, 'Check-in saved');
    } else {
      TracendToast.show(context, switch (result) {
        _Sent.painRefused => chipNotRecorded,
        _ when withPain => painQueuedToast,
        _ =>
          'Check-in saved on this device. It will sync when you are '
              'online.',
      }, icon: CupertinoIcons.cloud_upload);
    }
    Navigator.pop(context, CheckInSaved(delivered: result == _Sent.delivered));
  }

  /// Keeps the envelope on the phone, then sends it through the queue, so any
  /// older envelope that waits goes first and this one last (the server counts
  /// the last one sent as the day's check-in). A delivered check-in leaves the
  /// queue; one whose pain answers the server refuses stays, marked, so the
  /// athlete is told and the rest of it is not lost; anything else waits to be
  /// replayed. Never throws, and does not need the sheet to be open.
  Future<_Sent> _persistAndSend(
    Map<String, dynamic> payload,
    String localDate,
    String timezone,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final queue = CheckInQueue(
        preferences,
        userId: widget.environment.hasSupabaseConfiguration
            ? Supabase.instance.client.auth.currentUser?.id
            : null,
      );
      await queue.enqueue(
        payload: payload,
        localDate: localDate,
        timezone: timezone,
      );
      final outcome = await queue.replay(_send);
      return switch (outcome) {
        CheckInReplayOutcome.delivered => _Sent.delivered,
        CheckInReplayOutcome.painRefused => _Sent.painRefused,
        _ => _Sent.waiting,
      };
    } on Object catch (error) {
      debugPrint('Non-critical error: check-in waits: $error');
      return _Sent.waiting;
    }
  }

  Future<bool> _send(
    String localDate,
    String timezone,
    String idempotencyKey,
    Map<String, dynamic> payload,
  ) async {
    final sender = widget.sender;
    if (sender != null) {
      return sender(localDate, timezone, idempotencyKey, payload);
    }
    if (widget.environment.hasSupabaseConfiguration) {
      await Supabase.instance.client.rpc(
        'save_daily_check_in',
        params: {
          'local_date': localDate,
          'timezone': timezone,
          'idempotency_key': idempotencyKey,
          'payload': payload,
        },
      );
    }
    return true;
  }

  static bool _isPainKey(String key) =>
      key.startsWith('pain_') && key != 'pain_severity';

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
                Text(
                  'Use what you know now. Missing Apple Health data does not '
                  'block training.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: TracendSpacing.lg),
                for (final scale in checkInScales) ...[
                  _ScaleQuestion(
                    scale: scale,
                    value: _values[scale.key]!,
                    onChanged: (value) =>
                        setState(() => _values[scale.key] = value),
                  ),
                  const SizedBox(height: TracendSpacing.lg),
                ],
                for (final joint in widget.jointStates) ...[
                  _FollowUpQuestion(
                    joint: joint,
                    followUp: _followUps.putIfAbsent(joint.area, _FollowUp.new),
                    answeredBelow: _painReported && _area == joint.area,
                    missing: _followMissing.contains(joint.area),
                    onChanged: () =>
                        setState(() => _followMissing.remove(joint.area)),
                  ),
                  const SizedBox(height: TracendSpacing.lg),
                ],
                _PainQuestion(
                  reported: _painReported,
                  severity: _pain,
                  missing: _painMissing,
                  area: _area,
                  areaMissing: _areaMissing,
                  pattern: _pattern,
                  flags: _flags,
                  noneOfThese: _noneOfThese,
                  flagsMissing: _flagsMissing,
                  onReported: (reported) => setState(() {
                    _painReported = reported;
                    _painMissing = false;
                    _areaMissing = false;
                    _flagsMissing = false;
                    if (!reported) {
                      _pain = 0;
                      _area = null;
                      _pattern = null;
                      _flags.clear();
                      _noneOfThese = false;
                    }
                  }),
                  onSeverity: (value) => setState(() {
                    _pain = value;
                    _painMissing = false;
                  }),
                  onArea: (area) => setState(() {
                    _area = area;
                    _areaMissing = false;
                    // Only the questions this area asks stay answered.
                    _flags.retainWhere(redFlagCodesFor(area).contains);
                  }),
                  onPattern: (pattern) => setState(() => _pattern = pattern),
                  onFlag: (code) => setState(() {
                    if (!_flags.remove(code)) _flags.add(code);
                    _noneOfThese = false;
                    _flagsMissing = false;
                  }),
                  onNone: () => setState(() {
                    _noneOfThese = !_noneOfThese;
                    if (_noneOfThese) _flags.clear();
                    _flagsMissing = false;
                  }),
                ),
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
                      'Available to train today',
                      style: textTheme.titleSmall,
                    ),
                    value: _available,
                    onChanged: (value) {
                      TracendHaptics.light();
                      setState(() => _available = value);
                    },
                  ),
                ),
                const SizedBox(height: TracendSpacing.lg),
                TextField(
                  controller: _note,
                  maxLength: _noteLimit,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => currentLength < _counterFrom
                      ? null
                      : Text(
                          '${_noteLimit - currentLength} characters left',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                ),
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
              child: Text(_saving ? 'Saving…' : 'Save check-in'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A five-point question as a vertical selection list: full-width rows of at
/// least 48pt with wrapping text and a check on the chosen answer. It fits a
/// 320pt screen at the largest text sizes, which a five-label segmented
/// control cannot.
class _ScaleQuestion extends StatelessWidget {
  const _ScaleQuestion({
    required this.scale,
    required this.value,
    required this.onChanged,
  });

  final CheckInScale scale;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChoiceGroup(
      title: scale.title,
      options: [
        for (var i = 0; i < scale.labels.length; i++)
          (
            label: scale.labels[i],
            selected: scale.valueAt(i) == value,
            onTap: () => onChanged(scale.valueAt(i)),
          ),
      ],
    );
  }
}

/// How an area that was already held, limited or on watch is today. A held
/// area asks whether a doctor or physio has cleared it; any other asks
/// whether the pain is gone.
enum _FollowChoice { gone, still, cleared, notYet }

class _FollowUp {
  _FollowChoice? choice;
  int? severity;

  bool get needsStrength =>
      choice == _FollowChoice.still || choice == _FollowChoice.cleared;

  bool get answered =>
      choice == _FollowChoice.gone || (needsStrength && severity != null);

  int get reportedSeverity => choice == _FollowChoice.gone ? 0 : severity ?? 0;

  bool get cleared => choice == _FollowChoice.cleared;
}

class _FollowUpQuestion extends StatelessWidget {
  const _FollowUpQuestion({
    required this.joint,
    required this.followUp,
    required this.answeredBelow,
    required this.missing,
    required this.onChanged,
  });

  final JointState joint;
  final _FollowUp followUp;

  /// The athlete reports this area again as today's pain, below.
  final bool answeredBelow;
  final bool missing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final held = joint.state == JointStateKind.held;
    final title = held ? clearedTitle(joint.area) : followUpTitle(joint.area);
    if (answeredBelow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            'You are answering for this area below.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }
    void pick(_FollowChoice choice) {
      followUp.choice = choice;
      if (!followUp.needsStrength) followUp.severity = null;
      onChanged();
    }

    final first = held ? _FollowChoice.cleared : _FollowChoice.gone;
    final second = held ? _FollowChoice.notYet : _FollowChoice.still;
    String label(_FollowChoice choice) => switch (choice) {
      _FollowChoice.gone => followUpGone,
      _FollowChoice.still => followUpStillThere,
      _FollowChoice.cleared => followUpYes,
      _FollowChoice.notYet => followUpNotYet,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceGroup(
          title: title,
          options: [
            for (final choice in [first, second])
              (
                label: label(choice),
                selected: followUp.choice == choice,
                onTap: () => pick(choice),
              ),
          ],
        ),
        if (followUp.needsStrength) ...[
          const SizedBox(height: TracendSpacing.md),
          Text(
            followUp.cleared
                ? followUpStrengthTitle
                : 'How strong, from 1 to 10?',
            style: textTheme.titleSmall,
          ),
          if (followUp.cleared) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              followUpStrengthHint,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: TracendSpacing.sm),
          Wrap(
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            children: [
              for (var level = followUp.cleared ? 0 : 1; level <= 10; level++)
                SeverityChip(
                  level: level,
                  selected: followUp.severity == level,
                  onTap: () {
                    followUp.severity = level;
                    onChanged();
                  },
                ),
            ],
          ),
          if (missing) ...[
            const SizedBox(height: TracendSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                followUpStrengthRequired,
                style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Pain: "No pain" or "Some pain", and for some pain how strong it is from
/// 1 to 10 (`pain_severity`, 0–10 as before), where it is, when it hurts and
/// the red-flag questions for that area. Save stays closed until the area and
/// the red-flag answer are given.
class _PainQuestion extends StatelessWidget {
  const _PainQuestion({
    required this.reported,
    required this.severity,
    required this.missing,
    required this.area,
    required this.areaMissing,
    required this.pattern,
    required this.flags,
    required this.noneOfThese,
    required this.flagsMissing,
    required this.onReported,
    required this.onSeverity,
    required this.onArea,
    required this.onPattern,
    required this.onFlag,
    required this.onNone,
  });

  final bool reported;
  final int severity;
  final bool missing;
  final PainArea? area;
  final bool areaMissing;
  final String? pattern;
  final Set<String> flags;
  final bool noneOfThese;
  final bool flagsMissing;
  final ValueChanged<bool> onReported;
  final ValueChanged<int> onSeverity;
  final ValueChanged<PainArea> onArea;
  final ValueChanged<String?> onPattern;
  final ValueChanged<String> onFlag;
  final VoidCallback onNone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final chosen = area;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceGroup(
          title: 'Pain',
          options: [
            (
              label: 'No pain',
              selected: !reported,
              onTap: () => onReported(false),
            ),
            (
              label: 'Some pain',
              selected: reported,
              onTap: () => onReported(true),
            ),
          ],
        ),
        if (reported) ...[
          const SizedBox(height: TracendSpacing.md),
          Text('How strong, from 1 to 10?', style: textTheme.titleSmall),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '1 is barely noticeable, 10 is the worst you can imagine.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Wrap(
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            children: [
              for (var level = 1; level <= 10; level++)
                SeverityChip(
                  level: level,
                  selected: severity == level,
                  onTap: () => onSeverity(level),
                ),
            ],
          ),
          if (missing) ...[
            const SizedBox(height: TracendSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                painStrengthRequired,
                style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
              ),
            ),
          ],
          const SizedBox(height: TracendSpacing.lg),
          ChoiceGroup(
            title: painWhereTitle,
            options: [
              for (final option in PainArea.values)
                (
                  label: areaChoice(option),
                  selected: chosen == option,
                  onTap: () => onArea(option),
                ),
            ],
          ),
          if (areaMissing) ...[
            const SizedBox(height: TracendSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                painWhereRequired,
                style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
              ),
            ),
          ],
          const SizedBox(height: TracendSpacing.lg),
          ChoiceGroup(
            title: painWhenTitle,
            options: [
              (
                label: painWhenMove,
                selected: pattern == 'movement',
                onTap: () => onPattern('movement'),
              ),
              (
                label: painWhenRest,
                selected: pattern == 'rest',
                onTap: () => onPattern('rest'),
              ),
            ],
          ),
          if (chosen != null) ...[
            const SizedBox(height: TracendSpacing.lg),
            ChoiceGroup(
              title: redFlagsTitle,
              exclusive: false,
              options: [
                for (final code in redFlagCodesFor(chosen))
                  (
                    label: redFlagQuestion(code) ?? code,
                    selected: flags.contains(code),
                    onTap: () => onFlag(code),
                  ),
                (label: redFlagsNone, selected: noneOfThese, onTap: onNone),
              ],
            ),
            if (flagsMissing) ...[
              const SizedBox(height: TracendSpacing.xs),
              Semantics(
                liveRegion: true,
                child: Text(
                  redFlagsRequired,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.stateDanger,
                  ),
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
