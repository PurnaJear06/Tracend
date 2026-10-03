import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/rpe_picker.dart';
import 'package:tracend/features/train/widgets/set_row.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Whether the exercise history behind "Last time" and "Your best" is known.
enum HistoryStatus {
  /// Still asking the server.
  loading,

  /// Loaded (from the server or this phone's copy).
  ready,

  /// Neither the server nor this phone has it: nothing can be said.
  unavailable,
}

/// A new best to celebrate on the page: [set] just beat the record.
/// [token] changes for every new moment so a repeat plays again.
@immutable
class NewBestMoment {
  const NewBestMoment({required this.set, required this.token});

  final int set;
  final int token;
}

/// "Rest 1:30 after" / "Rest 45 s after".
String _restAfter(int seconds) {
  if (seconds >= 60) {
    final rest = seconds % 60;
    return 'Rest ${seconds ~/ 60}:${rest.toString().padLeft(2, '0')} after';
  }
  return 'Rest $seconds s after';
}

/// One exercise filling the screen in focus mode: big kg × reps with −/+,
/// a big "Done set N", set dots, last time and best, the exercise's muscles,
/// the sets already logged (with effort and undo), and the pain chip.
class FocusExercisePage extends StatefulWidget {
  const FocusExercisePage({
    required this.index,
    required this.count,
    required this.draft,
    required this.history,
    required this.historyStatus,
    required this.newBests,
    required this.onDone,
    required this.onLoadChanged,
    required this.onRepsChanged,
    required this.onUndo,
    required this.onRpe,
    required this.onFillRpe,
    required this.onPain,
    required this.onMore,
    this.nextExerciseName,
    this.onNext,
    this.moment,
    this.readOnly = false,
    super.key,
  });

  final int index;
  final int count;
  final ExerciseDraft draft;
  final ExerciseHistory? history;
  final HistoryStatus historyStatus;

  /// Sets of this exercise that are new bests right now.
  final Set<int> newBests;

  /// Finishes the current set with the kg and reps on screen.
  final void Function(String load, String reps) onDone;

  /// The athlete changed the current set's kg or reps.
  final ValueChanged<String> onLoadChanged;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<int> onUndo;

  /// Sets or clears (null) one set's effort.
  final void Function(int set, int? rpe) onRpe;

  /// Gives every logged set without an effort [rpe]; returns how many.
  final int Function(int rpe) onFillRpe;
  final VoidCallback onPain;
  final VoidCallback onMore;
  final String? nextExerciseName;
  final VoidCallback? onNext;
  final NewBestMoment? moment;

  /// A finished workout: the log only, nothing editable.
  final bool readOnly;

  @override
  State<FocusExercisePage> createState() => _FocusExercisePageState();
}

class _FocusExercisePageState extends State<FocusExercisePage>
    with SingleTickerProviderStateMixin {
  /// Burst 0–900 ms, stamp in 0–560 ms, held, out 2400–2800 ms.
  late final AnimationController _moment;

  /// The open effort picker: a set index, [_fill] for "Fill effort", or null.
  int? _picker;
  static const _fill = -1;

  @override
  void initState() {
    super.initState();
    _moment = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void didUpdateWidget(FocusExercisePage old) {
    super.didUpdateWidget(old);
    final moment = widget.moment;
    if (moment != null && moment.token != old.moment?.token) _celebrate();
    final picker = _picker;
    if (picker != null &&
        picker != _fill &&
        (picker >= widget.draft.sets.length ||
            !widget.draft.sets[picker].completed)) {
      _picker = null;
    }
  }

  void _celebrate() {
    if (TracendMotionScope.of(context) == TracendMotionLevel.static) return;
    _moment.forward(from: 0);
  }

  @override
  void dispose() {
    _moment.dispose();
    super.dispose();
  }

  double _phase(double startMs, double endMs, [Curve curve = Curves.linear]) {
    final t = ((_moment.value * 2800 - startMs) / (endMs - startMs)).clamp(
      0.0,
      1.0,
    );
    return curve.transform(t);
  }

  void _openFill() {
    if (widget.draft.completedCount == 0) {
      TracendToast.show(
        context,
        'Log a set first',
        icon: CupertinoIcons.info_circle,
      );
      return;
    }
    setState(() => _picker = _fill);
  }

  void _fillWith(int rpe) {
    final filled = widget.onFillRpe(rpe);
    setState(() => _picker = null);
    TracendToast.show(
      context,
      filled == 0
          ? 'Every logged set already has an effort'
          : 'Effort $rpe added to $filled ${filled == 1 ? 'set' : 'sets'}',
      icon: CupertinoIcons.gauge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final draft = widget.draft;
    final exercise = draft.exercise;
    final current = widget.readOnly ? null : draft.currentSetIndex;
    final muscles = exercise.exerciseSlug == null
        ? const <MuscleSets>[]
        : muscleSetsFor([exercise]);
    final compact = MediaQuery.sizeOf(context).width < 360;
    // With large text the name gets the full width and the figures sit
    // under it, so a long word never breaks mid-word beside them.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final map = muscles.isEmpty
        ? null
        : MuscleMapPair(
            muscles: muscleTones(muscles),
            palette: Theme.of(context).brightness == Brightness.dark
                ? MuscleMapPalette.dark
                : MuscleMapPalette.light,
            figureWidth: compact ? 32 : 40,
            spacing: 4,
          );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exercise ${widget.index + 1} of ${widget.count}'
          '${draft.skipped ? ', skipped' : ''}',
          style: text.labelSmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Text(
              exercise.name,
              style: (stacked ? text.headlineMedium : text.displaySmall)
                  ?.copyWith(height: 1.05),
            ),
          ),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          '${exercise.setCount} sets of ${exercise.repMin == exercise.repMax ? exercise.repMin : '${exercise.repMin}–${exercise.repMax}'}'
          ' · RPE ${formatKg(exercise.targetRpe)}',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        if (muscles.isNotEmpty)
          Text(
            muscles.map((m) => m.group.label).join(', '),
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
      ],
    );
    final header = map == null
        ? titleBlock
        : stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: TracendSpacing.xs),
              map,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: TracendSpacing.sm),
              map,
            ],
          );

    final dots = Semantics(
      label: '${draft.completedCount} of ${draft.sets.length} sets done',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < draft.sets.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 44),
                child: AnimatedContainer(
                  duration: TracendMotionScope.fade(
                    context,
                    TracendMotion.standard,
                  ),
                  height: 6,
                  decoration: BoxDecoration(
                    color: draft.sets[i].completed
                        ? colors.stateStable
                        : i == current
                        ? colors.accentSignal
                        : colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final logged = <Widget>[
      for (var i = 0; i < draft.sets.length; i++)
        if (draft.sets[i].completed)
          LoggedSetRow(
            key: ValueKey('logged-${widget.index}-$i'),
            number: i + 1,
            description: describeSet(
              loadKg: draft.sets[i].loadKg,
              repetitions: draft.sets[i].repetitions,
              assisted: draft.assisted,
            ),
            mark: widget.newBests.contains(i)
                ? SetMark.newBest
                : (widget.history?.isFirstLog ?? false) &&
                      i == draft.sets.indexWhere((s) => s.completed)
                ? SetMark.firstLog
                : null,
            rpe: draft.sets[i].rpeValue,
            onEffort: widget.readOnly
                ? null
                : () => setState(() => _picker = _picker == i ? null : i),
            onUndo: widget.readOnly ? null : () => widget.onUndo(i),
          ),
    ];

    final picker = _picker;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.gutter,
          TracendSpacing.xs,
          TracendSpacing.gutter,
          120,
        ),
        children: [
          header,
          const SizedBox(height: TracendSpacing.md),
          dots,
          const SizedBox(height: TracendSpacing.md),
          if (widget.readOnly)
            ..._readOnlyBody(context, logged)
          else ...[
            _card(context, current),
            const SizedBox(height: TracendSpacing.sm),
            _primaryAction(context, current),
            if (logged.isNotEmpty) ...[
              const SizedBox(height: TracendSpacing.lg),
              Text('Logged', style: text.titleSmall),
              const SizedBox(height: TracendSpacing.xxs),
              ...logged,
            ],
            if (picker != null) ...[
              const SizedBox(height: TracendSpacing.sm),
              if (picker == _fill)
                RpePicker(
                  title: 'Fill effort for sets without one',
                  value: null,
                  onSelected: _fillWith,
                  dismissLabel: 'Cancel',
                  onDismiss: () => setState(() => _picker = null),
                )
              else
                RpePicker(
                  title: 'Effort for set ${picker + 1}',
                  value: draft.sets[picker].rpeValue,
                  onSelected: (value) {
                    widget.onRpe(picker, value);
                    setState(() => _picker = null);
                  },
                  onClear: () => widget.onRpe(picker, null),
                  dismissLabel: 'Not now',
                  onDismiss: () => setState(() => _picker = null),
                ),
            ],
            const SizedBox(height: TracendSpacing.md),
            _tools(context),
            if (widget.nextExerciseName != null) ...[
              const SizedBox(height: TracendSpacing.lg),
              ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Swipe for ${widget.nextExerciseName}',
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_right_2,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _readOnlyBody(BuildContext context, List<Widget> logged) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    return [
      if (widget.draft.pain)
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: 'Pain noted',
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            tone: StatusTone.caution,
          ),
        ),
      if (widget.draft.pain) const SizedBox(height: TracendSpacing.sm),
      if (logged.isEmpty)
        Text(
          widget.draft.skipped
              ? 'Skipped in this workout.'
              : 'No sets were logged for this exercise.',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        )
      else
        TracendCard(child: Column(children: logged)),
    ];
  }

  Widget _card(BuildContext context, int? current) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final draft = widget.draft;
    final exercise = draft.exercise;
    final Widget body;
    if (current == null) {
      final next = widget.nextExerciseName;
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: TracendSpacing.md),
        child: Column(
          children: [
            Text(
              'All ${draft.sets.length} sets done',
              textAlign: TextAlign.center,
              style: text.headlineMedium,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              next == null
                  ? 'That was the last exercise. Tap Finish when you are ready.'
                  : 'Swipe for $next',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    } else {
      final suggestion = suggestSet(draft, current, widget.history);
      final source = switch (suggestion.source) {
        SetSuggestionSource.entered => null,
        SetSuggestionSource.earlierSet => 'From your last set',
        SetSuggestionSource.lastTime => 'From last time',
        SetSuggestionSource.plan => 'From your plan',
      };
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: TracendSpacing.xs,
            children: [
              Text(
                'Set ${current + 1} of ${draft.sets.length}',
                style: text.titleSmall?.copyWith(color: colors.textSecondary),
              ),
              if (exercise.restSeconds > 0)
                Text(
                  _restAfter(exercise.restSeconds),
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BigNumber(
                  key: ValueKey('kg-${widget.index}-$current'),
                  value: suggestion.load,
                  unit: draft.assisted ? 'kg help' : 'kg',
                  fieldLabel: 'Set ${current + 1} weight in kilograms',
                  decimal: true,
                  lessLabel: 'Less weight',
                  moreLabel: 'More weight',
                  onChanged: widget.onLoadChanged,
                  onStep: (direction) => widget.onLoadChanged(
                    _stepLoad(suggestion.load, direction, draft.assisted),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: ExcludeSemantics(
                  child: Text(
                    '×',
                    style: TracendTheme.numeric(
                      colors,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _BigNumber(
                  key: ValueKey('reps-${widget.index}-$current'),
                  value: suggestion.reps,
                  unit: 'reps',
                  fieldLabel: 'Set ${current + 1} reps',
                  decimal: false,
                  lessLabel: 'One less rep',
                  moreLabel: 'One more rep',
                  onChanged: widget.onRepsChanged,
                  onStep: (direction) => widget.onRepsChanged(
                    _stepReps(suggestion.reps, direction),
                  ),
                ),
              ),
            ],
          ),
          if (source != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            Text(
              source,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            const SizedBox(height: TracendSpacing.sm),
            Divider(height: 1, thickness: 1, color: colors.borderHairline),
            const SizedBox(height: TracendSpacing.sm),
            _historyStrip(context),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _moment,
      builder: (context, child) {
        if (!_moment.isAnimating && _moment.value == 0) return child!;
        final full = TracendMotionScope.of(context) == TracendMotionLevel.full;
        final inT = _phase(0, 560, Curves.easeOutBack);
        final out = 1 - _phase(2400, 2800);
        final opacity = (full ? _phase(0, 200) : _phase(0, 240)) * out;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (_moment.value < 1)
              Positioned(
                top: 10,
                right: 12,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform(
                      alignment: Alignment.center,
                      transform:
                          Matrix4.rotationZ(
                            full ? -0.07 - 0.17 * (1 - inT) : -0.07,
                          )..scaleByDouble(
                            full ? 1 + 1.2 * (1 - inT) : 1,
                            full ? 1 + 1.2 * (1 - inT) : 1,
                            1,
                            1,
                          ),
                      child: const NewBestStamp(large: true),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: card,
    );
  }

  Widget _historyStrip(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: colors.textSecondary);
    switch (widget.historyStatus) {
      case HistoryStatus.loading:
        return Semantics(
          label: 'Loading last time and best',
          child: const TracendSkeleton.line(widthFactor: 0.7),
        );
      case HistoryStatus.unavailable:
        return Text('Last time and best need a connection.', style: muted);
      case HistoryStatus.ready:
        break;
    }
    final history = widget.history;
    if (history == null) {
      return Text('Last time and best need a connection.', style: muted);
    }
    if (history.isFirstLog) {
      return Row(
        children: [
          const FirstLogTag(),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Text('No earlier sets for this exercise.', style: muted),
          ),
        ],
      );
    }
    final current = widget.draft.currentSetIndex ?? 0;
    final last = lastTimeSet(history, current);
    final lastText = last == null
        ? null
        : describeSet(
            loadKg: last.loadKg,
            repetitions: last.repetitions,
            assisted: widget.draft.assisted,
          );
    final best = describeBest(history.bestSet);
    Widget item(String label, String? value) => Text.rich(
      TextSpan(
        text: '$label ',
        children: [
          TextSpan(
            text: value == null || value.isEmpty
                ? 'Not enough data yet'
                : value,
            style: TracendTheme.numeric(
              colors,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      style: muted,
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: TracendSpacing.md,
      runSpacing: TracendSpacing.xxs,
      children: [item('Last time', lastText), item('Your best', best)],
    );
  }

  Widget _primaryAction(BuildContext context, int? current) {
    final full = TracendMotionScope.of(context) == TracendMotionLevel.full;
    final Widget button;
    if (current == null) {
      final onNext = widget.onNext;
      if (onNext == null) return const SizedBox.shrink();
      button = OutlinedButton.icon(
        onPressed: onNext,
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 60)),
        iconAlignment: IconAlignment.end,
        icon: const Icon(CupertinoIcons.arrow_right, size: 18),
        label: const Text('Next exercise'),
      );
    } else {
      final suggestion = suggestSet(widget.draft, current, widget.history);
      final ready = (num.tryParse(suggestion.reps) ?? 0) > 0;
      button = FilledButton(
        onPressed: ready
            ? () => widget.onDone(suggestion.load, suggestion.reps)
            : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 60),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontSize: 18),
        ),
        child: Text('Done set ${current + 1}'),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        SizedBox(width: double.infinity, child: button),
        if (full)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _moment,
                builder: (context, _) {
                  final t = _phase(0, 900);
                  if (t <= 0 || t >= 1) return const SizedBox.shrink();
                  return CustomPaint(
                    painter: _BurstPainter(
                      progress: t,
                      color: context.tracendColors.accentSignalRing,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _tools(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final draft = widget.draft;
    Widget pill({
      required String label,
      required IconData icon,
      required VoidCallback onTap,
      Color? fill,
      Color? ink,
      bool? toggled,
    }) => Semantics(
      toggled: toggled,
      child: Pressable(
        onTap: onTap,
        haptic: TracendHaptics.light,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill ?? colors.surfaceRaised,
                borderRadius: BorderRadius.circular(TracendRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TracendSpacing.sm,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: ink ?? colors.textPrimary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: text.labelMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: TracendSpacing.xs,
            runSpacing: 0,
            children: [
              pill(
                label: draft.pain ? 'Pain noted' : 'Pain or discomfort',
                icon: draft.pain
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : CupertinoIcons.hand_raised,
                fill: draft.pain
                    ? colors.accentAmber.withValues(alpha: 0.16)
                    : null,
                ink: draft.pain ? colors.accentAmber : null,
                toggled: draft.pain,
                onTap: widget.onPain,
              ),
              pill(
                label: 'Fill effort',
                icon: CupertinoIcons.gauge,
                onTap: _openFill,
              ),
            ],
          ),
        ),
        Pressable(
          onTap: widget.onMore,
          semanticLabel: 'More for ${draft.exercise.name}',
          borderRadius: BorderRadius.circular(TracendRadii.pill),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              CupertinoIcons.ellipsis,
              size: 20,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

String _stepLoad(String value, int direction, bool assisted) {
  final current = num.tryParse(value) ?? 0;
  final next = math.min(2000, math.max(0, current + 2.5 * direction));
  if (next == 0 && !assisted) return '';
  return formatKg(next);
}

String _stepReps(String value, int direction) {
  final current = num.tryParse(value)?.toInt() ?? 0;
  return '${math.min(100, math.max(1, current + direction))}';
}

/// A big editable number with − and + below it. Typing works too, so a
/// 100 kg lift never takes forty taps.
class _BigNumber extends StatefulWidget {
  const _BigNumber({
    required this.value,
    required this.unit,
    required this.fieldLabel,
    required this.decimal,
    required this.lessLabel,
    required this.moreLabel,
    required this.onChanged,
    required this.onStep,
    super.key,
  });

  final String value;
  final String unit;
  final String fieldLabel;
  final bool decimal;
  final String lessLabel;
  final String moreLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onStep;

  @override
  State<_BigNumber> createState() => _BigNumberState();
}

class _BigNumberState extends State<_BigNumber>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  /// The nudge when − or + changes the number: up for more, down for less.
  late final AnimationController _bump;
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    _bump = AnimationController(vsync: this, duration: TracendMotion.quick);
  }

  @override
  void didUpdateWidget(_BigNumber old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _bump.dispose();
    super.dispose();
  }

  void _step(int direction) {
    _focus.unfocus();
    _direction = direction;
    if (TracendMotionScope.of(context) == TracendMotionLevel.full) {
      _bump.forward(from: 0);
    }
    widget.onStep(direction);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    // The readout is already 64 pt; it grows a little with the text size
    // but never past what fits half a phone.
    final scaler = media.textScaler.clamp(maxScaleFactor: 1.2);
    Widget stepButton(
      String glyph,
      String label,
      int direction,
      double width,
    ) => Pressable(
      onTap: () => _step(direction),
      haptic: TracendHaptics.selection,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(TracendRadii.pill),
        ),
        child: Text(
          glyph,
          textScaler: TextScaler.noScaling,
          style: TracendTheme.numeric(
            colors,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(64.0, constraints.maxWidth * 0.46);
        // Two 44 pt targets side by side, wider when there is room.
        final stepWidth = ((constraints.maxWidth - 6) / 2).clamp(44.0, 48.0);
        // One VoiceOver element: "Set 1 weight in kilograms, 60, text field".
        final field = MergeSemantics(
          child: Column(
            children: [
              MediaQuery(
                data: media.copyWith(textScaler: scaler),
                child: AnimatedBuilder(
                  animation: _bump,
                  builder: (context, child) {
                    final t = _bump.isAnimating
                        ? 1 - Curves.easeOut.transform(_bump.value)
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(0, -6 * _direction * t),
                      child: Opacity(opacity: 1 - 0.6 * t, child: child),
                    );
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: widget.decimal,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        widget.decimal
                            ? RegExp(r'^\d{0,4}([.,]\d{0,2})?')
                            : RegExp(r'^\d{0,3}'),
                      ),
                    ],
                    style: TracendTheme.numeric(
                      colors,
                      fontSize: size,
                      fontWeight: FontWeight.w800,
                    ).copyWith(height: 1.05, letterSpacing: -1.5),
                    decoration: InputDecoration.collapsed(
                      hintText: '–',
                      hintStyle: TracendTheme.numeric(
                        colors,
                        fontSize: size,
                        fontWeight: FontWeight.w800,
                        color: colors.textTertiary,
                      ),
                    ),
                    onChanged: (value) =>
                        widget.onChanged(value.replaceAll(',', '.')),
                    onTapOutside: (_) => _focus.unfocus(),
                  ),
                ),
              ),
              Semantics(
                label: widget.fieldLabel,
                excludeSemantics: true,
                child: Text(
                  widget.unit,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
        return Column(
          children: [
            field,
            const SizedBox(height: TracendSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                stepButton('−', widget.lessLabel, -1, stepWidth),
                const SizedBox(width: 6),
                stepButton('+', widget.moreLabel, 1, stepWidth),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The new-best burst: one lime ring opening out and short rays flying from
/// the button. A burst, not confetti: it draws for 900 ms and is gone.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const _rays = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * fade + 1
      ..color = color.withValues(alpha: fade);
    canvas.drawCircle(center, 18 + 92 * eased, ring);
    final ray = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = color.withValues(alpha: fade);
    for (var i = 0; i < _rays; i++) {
      final angle = i / _rays * math.pi * 2 + 0.2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final reach = (i.isEven ? 120 : 92) * eased;
      final start = center + direction * (34 + reach * 0.7);
      final end = center + direction * (40 + reach);
      canvas.drawLine(start, end, ray);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
