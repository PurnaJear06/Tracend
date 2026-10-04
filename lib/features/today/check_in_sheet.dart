import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Opens the daily check-in sheet. [sender] replaces the
/// `save_daily_check_in` RPC (tests inject a recording fake); without it the
/// sheet calls Supabase when the environment is configured.
/// Resolves true when the check-in was saved, delivered or queued on this
/// device, and false when the sheet was dismissed.
Future<bool> showCheckInSheet(
  BuildContext context,
  AppEnvironment environment, {
  CheckInSend? sender,
}) async =>
    await showTracendSheet<bool>(
      context,
      title: 'Daily check-in',
      scrollable: false,
      padding: EdgeInsets.zero,
      builder: (_) => _CheckInSheet(environment: environment, sender: sender),
    ) ??
    false;

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

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({required this.environment, required this.sender});

  final AppEnvironment environment;
  final CheckInSend? sender;

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
  final _note = TextEditingController();
  bool _available = true;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_painReported && _pain == 0) {
      unawaited(TracendHaptics.warning());
      setState(() => _painMissing = true);
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final localDate = now.toIso8601String().substring(0, 10);
    final timezone = now.timeZoneName;
    final payload = {
      for (final scale in checkInScales) scale.key: _values[scale.key]!,
      'pain_severity': _pain,
      'available_to_train': _available,
      'note': _note.text.trim(),
    };
    // The envelope is queued before the RPC so the check-in survives a lost
    // connection; Today retries it on the next launch via CheckInQueue.
    final preferences = await SharedPreferences.getInstance();
    final queue = CheckInQueue(
      preferences,
      userId: widget.environment.hasSupabaseConfiguration
          ? Supabase.instance.client.auth.currentUser?.id
          : null,
    );
    final idempotencyKey = await queue.enqueue(
      payload: payload,
      localDate: localDate,
      timezone: timezone,
    );
    var delivered = false;
    try {
      final sender = widget.sender;
      if (sender != null) {
        delivered = await sender(localDate, timezone, idempotencyKey, payload);
      } else {
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
        delivered = true;
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
    // An undelivered envelope stays queued; Today replays it next launch.
    if (delivered) await queue.clear();
    if (!mounted) return;
    if (delivered) {
      unawaited(TracendHaptics.success());
      TracendToast.show(context, 'Check-in saved');
    } else {
      TracendToast.show(
        context,
        'Check-in saved on this device. It will sync when you are online.',
        icon: CupertinoIcons.cloud_upload,
      );
    }
    Navigator.pop(context, true);
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
                _PainQuestion(
                  reported: _painReported,
                  severity: _pain,
                  missing: _painMissing,
                  onReported: (reported) => setState(() {
                    _painReported = reported;
                    _painMissing = false;
                    if (!reported) _pain = 0;
                  }),
                  onSeverity: (value) => setState(() {
                    _pain = value;
                    _painMissing = false;
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
    return _ChoiceGroup(
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

/// Pain: "No pain" or "Some pain", and for some pain how strong it is from
/// 1 to 10, stored as `pain_severity` 0–10 exactly as before.
class _PainQuestion extends StatelessWidget {
  const _PainQuestion({
    required this.reported,
    required this.severity,
    required this.missing,
    required this.onReported,
    required this.onSeverity,
  });

  final bool reported;
  final int severity;
  final bool missing;
  final ValueChanged<bool> onReported;
  final ValueChanged<int> onSeverity;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceGroup(
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
                _SeverityChip(
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
                'Choose how strong the pain is to save.',
                style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final int level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Pain $level of 10',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) TracendHaptics.selection();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.accentSignal : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(TracendRadii.pill),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.all(TracendSpacing.xs),
                child: Text(
                  '$level',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: TracendFonts.numericFamily,
                    color: selected
                        ? colors.onAccentSignal
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Choice = ({String label, bool selected, VoidCallback onTap});

/// A titled single-choice list on one `surface`: rows with hairline
/// separators and a lime check on the selected row.
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({required this.title, required this.options});

  final String title;
  final List<_Choice> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: TracendSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(title, style: textTheme.titleMedium),
          ),
        ),
        Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: TracendSpacing.md),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.borderHairline,
                    ),
                  ),
                _ChoiceRow(title: title, choice: options[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.title, required this.choice});

  final String title;
  final _Choice choice;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: choice.selected,
      inMutuallyExclusiveGroup: true,
      label: '$title: ${choice.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          if (!choice.selected) TracendHaptics.selection();
          choice.onTap();
        },
        highlightColor: colors.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.md,
              vertical: TracendSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    choice.label,
                    style: choice.selected
                        ? textTheme.titleSmall
                        : textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                ),
                const SizedBox(width: TracendSpacing.sm),
                SizedBox.square(
                  dimension: 20,
                  child: choice.selected
                      ? Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 20,
                          color: colors.accentSignalInk,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
