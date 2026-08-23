import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/targets_grid.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({
    this.repository = const FixtureNutritionRepository(),
    this.coach = const FixtureCoachRepository(),
    super.key,
  });

  final NutritionRepository repository;
  final CoachRepository coach;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _working = false;
  String? _error;
  NutritionTargets? _targets;
  NutritionSummary? _summary;
  List<MealEntry> _meals = const [];
  NutritionSchedule? _schedule;
  late Future<CoachDecision?> _decision;

  @override
  void initState() {
    super.initState();
    _decision = widget.coach.loadLatest();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.repository.loadTargets(),
        widget.repository.loadSummary(_date),
        widget.repository.loadMeals(_date),
        if (widget.repository is NutritionScheduleRepository)
          (widget.repository as NutritionScheduleRepository).loadSchedule(_date)
        else
          Future.value(
            const NutritionSchedule(title: 'Meal schedule', items: []),
          ),
      ]);
      if (!mounted) return;
      setState(() {
        _targets = values[0] as NutritionTargets?;
        _summary = values[1] as NutritionSummary;
        _meals = values[2] as List<MealEntry>;
        _schedule = values[3] as NutritionSchedule;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error = 'Nutrition data is unavailable. Pull to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDate(DateTime candidate) async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (candidate.isAfter(todayOnly)) return;
    if (candidate.year == _date.year &&
        candidate.month == _date.month &&
        candidate.day == _date.day) {
      return;
    }
    setState(() => _date = candidate);
    await _refresh();
  }

  bool get _isToday {
    final today = DateTime.now();
    return _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
  }

  bool get _isCurrentWeek => mondayOf(_date) == mondayOf(DateTime.now());

  String get _dateLabel => _isToday
      ? 'Today'
      : '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';

  Future<void> _openManualMeal([ScheduledMeal? scheduled]) async {
    final input = await showModalBottomSheet<ManualMealResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ManualMealSheet(),
    );
    if (input == null) return;
    await _run(() {
      final repository = widget.repository;
      if (scheduled != null && repository is ScheduledMealLogger) {
        return (repository as ScheduledMealLogger).saveScheduledMeal(
          date: _date,
          scheduleItemId: scheduled.id,
          mealType: input.mealType,
          food: input.food,
        );
      }
      return repository.saveManualMeal(
        date: _date,
        mealType: input.mealType,
        food: input.food,
      );
    });
  }

  Future<void> _reviewFixture() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final mealId = await widget.repository.createFixtureMeal(
        date: _date,
        mealType: 'lunch',
      );
      await _openCandidateReview(mealId);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Meal analysis is unavailable. Enter the meal manually instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _selectMealPhoto(ImageSource source) async {
    final repository = widget.repository;
    if (repository is! MealPhotoRepository) return;
    final photo = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
      requestFullMetadata: false,
    );
    if (photo == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final mealId = await (repository as MealPhotoRepository).analyzeMealPhoto(
        date: _date,
        mealType: 'lunch',
        bytes: await photo.readAsBytes(),
      );
      await _openCandidateReview(mealId);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Meal photo analysis is unavailable. Enter the meal manually; no estimate was added to totals.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openCandidateReview(String mealId) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final candidates = await widget.repository.loadCandidates(mealId);
      if (!mounted) return;
      setState(() => _working = false);
      final selected = await showModalBottomSheet<List<MealCandidate>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CandidateSheet(candidates: candidates),
      );
      if (selected == null || selected.isEmpty) return;
      await _run(() => widget.repository.confirmCandidates(mealId, selected));
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Draft could not be opened. Retry or delete it and enter the meal manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String failureMessage =
        'Meal was not saved. Your confirmed totals are unchanged.',
  }) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() => _error = failureMessage);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteMeal(MealEntry meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this meal?'),
        content: const Text(
          'The meal and its nutrition values will be removed from today’s totals. This action is recorded for account security.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete meal'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.repository.deleteMeal(meal.id),
      failureMessage:
          'Meal was not deleted. Your confirmed totals are unchanged.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final nextMeal = _isToday ? _schedule?.nextMeal : null;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return TracendScrollView(
      title: 'Nutrition',
      subtitle: 'Confirmed meals only · $_dateLabel',
      children: [
        DatePillStrip(
          selectedDate: _date,
          onSelectedDate: _selectDate,
          isDateEnabled: (date) => !date.isAfter(todayOnly),
          onPreviousWeek: () =>
              _selectDate(mondayOf(_date).subtract(const Duration(days: 7))),
          onNextWeek: _isCurrentWeek
              ? null
              : () => _selectDate(mondayOf(_date).add(const Duration(days: 7))),
        ),
        const SizedBox(height: TracendSpacing.md),
        if (_loading) const LinearProgressIndicator(minHeight: 3),
        if (_error != null) ...[
          TracendCard(
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: colors.stateAttention,
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.md),
        ],
        FutureBuilder<CoachDecision?>(
          future: _decision,
          builder: (context, snapshot) {
            final decision = snapshot.data;
            if (decision == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: TracendSpacing.md),
              child: NutritionInsightCard(decision: decision),
            );
          },
        ),
        if (nextMeal != null) ...[
          PremiumGradientCard(
            glow: true,
            glowColor: colors.accentAmber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TracendPill(
                  label:
                      '${nextMeal.status == 'due' ? 'Due now' : 'Next meal'} · ${nextMeal.time}',
                  icon: CupertinoIcons.clock_fill,
                  color: nextMeal.status == 'due'
                      ? colors.stateAttention
                      : colors.accentAmber,
                ),
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  nextMeal.label,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: TracendSpacing.xs),
                for (final food in nextMeal.foods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TracendSpacing.xxs),
                    child: Text('${food['name']} · ${food['quantity']}'),
                  ),
                const SizedBox(height: TracendSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _openManualMeal(nextMeal),
                    icon: const Icon(CupertinoIcons.check_mark_circled_solid),
                    label: const Text('Log meal'),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Confirmed nutrition'),
        ],
        TargetsGrid(summary: _summary, targets: _targets),
        if (_schedule != null && _schedule!.items.isNotEmpty) ...[
          const SectionLabel('Meal schedule'),
          PremiumGradientCard(
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.md,
              vertical: TracendSpacing.sm,
            ),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < _schedule!.items.length;
                  index++
                ) ...[
                  _ScheduledMealRow(item: _schedule!.items[index]),
                  if (index != _schedule!.items.length - 1)
                    Divider(
                      height: TracendSpacing.lg,
                      color: colors.borderHairline,
                    ),
                ],
              ],
            ),
          ),
        ],
        const SectionLabel('Add a meal'),
        FilledButton.icon(
          onPressed: _working ? null : _openManualMeal,
          icon: _working
              ? const TracendLoadingIndicator(size: 18)
              : const Icon(CupertinoIcons.pencil),
          label: const Text('Enter manually'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : widget.repository is MealPhotoRepository
              ? () => _selectMealPhoto(ImageSource.camera)
              : _reviewFixture,
          icon: const Icon(CupertinoIcons.camera_viewfinder),
          label: Text(
            widget.repository is MealPhotoRepository
                ? 'Analyze meal photo'
                : 'Review sample analysis',
          ),
        ),
        if (widget.repository is MealPhotoRepository) ...[
          const SizedBox(height: TracendSpacing.sm),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => _selectMealPhoto(ImageSource.gallery),
            icon: const Icon(CupertinoIcons.photo_on_rectangle),
            label: const Text('Choose from Photo Library'),
          ),
        ],
        const SizedBox(height: TracendSpacing.xs),
        Text(
          widget.repository is MealPhotoRepository
              ? 'AI candidates are estimates. Review portions, oil, sauces and hidden ingredients before confirmation.'
              : 'Sample analysis is a local fixture. Nothing affects totals until you confirm it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SectionLabel(_isToday ? 'Today’s timeline' : '$_dateLabel timeline'),
        if (!_loading && _meals.isEmpty)
          const TracendCard(
            child: Text(
              'No confirmed meals yet. Manual logging stays available when analysis is unavailable.',
            ),
          )
        else
          for (final meal in _meals) ...[
            _MealCard(
              meal: meal,
              onReview: meal.status == 'draft' && !_working
                  ? () => _openCandidateReview(meal.id)
                  : null,
              onDelete: _working ? null : () => _deleteMeal(meal),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
      ],
    );
  }
}

class _ScheduledMealRow extends StatelessWidget {
  const _ScheduledMealRow({required this.item});
  final ScheduledMeal item;
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final complete = item.status == 'logged';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: complete
                  ? colors.stateStable.withValues(alpha: 0.16)
                  : colors.surfaceRaised,
            ),
            child: Icon(
              complete ? CupertinoIcons.check_mark : CupertinoIcons.clock,
              size: 18,
              color: complete ? colors.stateStable : colors.textSecondary,
            ),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      item.time,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFamily: TracendFonts.monoFamily,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Text(
                  item.foods.map((food) => food['name']).join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  item.optional ? 'Optional · ${item.status}' : item.status,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.onReview,
    required this.onDelete,
  });
  final MealEntry meal;
  final VoidCallback? onReview;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final confirmed = meal.status == 'confirmed';
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                confirmed
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.clock,
                size: 18,
                color: confirmed ? colors.stateStable : colors.textSecondary,
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text(
                  meal.type,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                meal.status,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.textSecondary,
                ),
              ),
              IconButton(
                key: ValueKey('delete-meal-${meal.id}'),
                onPressed: onDelete,
                tooltip: 'Delete meal',
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: const Icon(CupertinoIcons.delete),
              ),
            ],
          ),
          if (meal.status == 'draft') ...[
            const SizedBox(height: TracendSpacing.xs),
            OutlinedButton.icon(
              key: ValueKey('review-meal-${meal.id}'),
              onPressed: onReview,
              icon: const Icon(CupertinoIcons.pencil),
              label: const Text('Review & edit draft'),
            ),
          ],
        ],
      ),
    );
  }
}
