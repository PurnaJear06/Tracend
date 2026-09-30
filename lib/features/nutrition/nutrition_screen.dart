import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/meal_cards.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/targets_grid.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Opens the camera or the photo library and returns the chosen photo, or
/// null when the user cancels.
typedef MealPhotoPicker = Future<XFile?> Function(ImageSource source);

Future<XFile?> _pickWithImagePicker(ImageSource source) =>
    ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
      requestFullMetadata: false,
    );

/// What the meal-photo area says when a photo fails. Access problems name the
/// setting to change; anything else names the failed step and its code.
String mealPhotoFailureMessage(
  MealPhotoFailure failure,
) => switch (failure.code) {
  'camera_access_denied' =>
    'Tracend cannot use the camera. Allow it in Settings › Tracend › Camera, or choose a photo from your library.',
  'photo_access_denied' =>
    'Tracend cannot open your photos. Allow it in Settings › Tracend › Photos.',
  'photo_too_large' => 'This photo is larger than 4 MB. Choose a smaller one.',
  // iOS could not hand over the photo, usually one kept only in iCloud that
  // did not download.
  'invalid_image' =>
    'This photo could not be loaded from your library. If it is stored in iCloud, try again on Wi-Fi, or take a photo instead.',
  '422 meal_no_food_found' =>
    'No food was found in this photo. Try a clear photo of the plate, or enter the meal manually.',
  '429 meal_vision_busy' =>
    'Photo analysis is busy: the free tier handles about one photo a minute. Wait a minute and try again.',
  '429 ai_usage_limit' =>
    'You have reached today’s AI limit (30 requests) or this month’s \$2 limit. Enter the meal manually.',
  _ =>
    'Meal photo analysis failed (${failure.step}: ${failure.code}). Enter the meal manually; nothing was added to your totals.',
};

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({
    this.repository = const FixtureNutritionRepository(),
    this.coach = const FixtureCoachRepository(),
    this.pickPhoto = _pickWithImagePicker,
    super.key,
  });

  final NutritionRepository repository;
  final CoachRepository coach;
  final MealPhotoPicker pickPhoto;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _working = false;
  String? _error;

  /// Shown under the photo buttons, where the user is looking; `_error` sits
  /// at the top of the screen, out of view from there.
  String? _photoError;
  bool _analyzingPhoto = false;
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
    setState(() => _photoError = null);
    final XFile? photo;
    try {
      photo = await widget.pickPhoto(source);
    } on PlatformException catch (error, stackTrace) {
      // A refused camera or photo permission ends here. Uncaught, it used to
      // make the button look dead.
      _photoFailed(MealPhotoFailure('picker', error.code), stackTrace);
      return;
    }
    if (photo == null || !mounted) return;
    setState(() {
      _working = true;
      _analyzingPhoto = true;
    });
    try {
      final mealId = await (repository as MealPhotoRepository).analyzeMealPhoto(
        date: _date,
        mealType: 'lunch',
        bytes: await photo.readAsBytes(),
      );
      if (!mounted) return;
      setState(() => _analyzingPhoto = false);
      await _openCandidateReview(mealId, fromPhoto: true);
    } catch (error, stackTrace) {
      _photoFailed(
        error is MealPhotoFailure
            ? error
            : MealPhotoFailure('app', error.runtimeType.toString()),
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _analyzingPhoto = false;
        });
      }
    }
  }

  void _photoFailed(MealPhotoFailure failure, StackTrace stackTrace) {
    debugPrint('Meal photo failed: $failure');
    unawaited(Sentry.captureException(failure, stackTrace: stackTrace));
    if (mounted) setState(() => _photoError = mealPhotoFailureMessage(failure));
  }

  Future<void> _openCandidateReview(
    String mealId, {
    bool fromPhoto = false,
  }) async {
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
      const message =
          'Draft could not be opened. Retry or delete it and enter the meal manually.';
      if (mounted) {
        setState(() {
          if (fromPhoto) {
            _photoError = message;
          } else {
            _error = message;
          }
        });
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
                  ScheduledMealRow(item: _schedule!.items[index]),
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
        if (_analyzingPhoto) ...[
          const SizedBox(height: TracendSpacing.sm),
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            'Analyzing meal photo…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_photoError != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          TracendCard(
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: colors.stateAttention,
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(child: Text(_photoError!)),
              ],
            ),
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
            MealCard(
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
