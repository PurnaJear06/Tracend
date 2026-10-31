import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/features/consent/widgets/ai_notice_panel.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/meal_cards.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/plan_changes.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/targets_grid.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

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
/// setting to change; anything else says plainly that analysis did not work,
/// and [mealPhotoFailureDiagnostic] adds the failed step and its code.
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
  // The notice changed between the check and the analysis; the next tap
  // shows the new one.
  '403 meal_photo_ai_consent_required' =>
    'The meal photo notice has changed. Tap the photo button again to review it.',
  '429 ai_usage_limit' =>
    'You have reached today’s AI limit (30 requests) or this month’s \$2 limit. Enter the meal manually.',
  _ =>
    'Photo analysis did not work this time. Enter the meal manually; nothing was added to your totals.',
};

/// The beta diagnostic shown under a photo failure that has no specific
/// message, so the failing step stays visible (owner decision 2026-10-01).
String? mealPhotoFailureDiagnostic(MealPhotoFailure failure) =>
    mealPhotoFailureMessage(failure).startsWith('Photo analysis did not work')
    ? 'Beta diagnostic · ${failure.step}: ${failure.code}'
    : null;

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({
    this.repository = const FixtureNutritionRepository(),
    this.coach = const FixtureCoachRepository(),
    this.pickPhoto = _pickWithImagePicker,
    this.planChanges,
    this.active = true,
    this.clock = DateTime.now,
    super.key,
  });

  /// Whether this tab is the one on screen. Opening it again reloads data
  /// that is not fresh.
  final bool active;

  /// The phone's clock, for the day Meals opens on and follows.
  final DateTime Function() clock;

  /// Reloads the targets when a Coach proposal changed them.
  final PlanChanges? planChanges;
  final NutritionRepository repository;
  final CoachRepository coach;
  final MealPhotoPicker pickPhoto;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  late DateTime _date = widget.clock();

  /// Set once the athlete picks another day than today. Until then the
  /// screen follows today, across midnight.
  bool _pickedDate = false;
  bool _loading = true;

  /// When the day's data last arrived, and which load started last: a reply
  /// for a day that is no longer shown is dropped.
  late final LoadStamp _loaded = LoadStamp(widget.clock);
  late final ResumeObserver _resume = ResumeObserver(_reloadIfStale);
  int _loads = 0;
  bool _working = false;
  String? _error;

  /// Shown under the photo buttons, where the user is looking; `_error` sits
  /// at the top of the screen, out of view from there.
  String? _photoError;
  String? _photoDiagnostic;
  bool _analyzingPhoto = false;
  NutritionTargets? _targets;
  NutritionSummary? _summary;
  List<MealEntry> _meals = const [];
  NutritionSchedule? _schedule;

  /// The day the shown totals and meals belong to; null before the first
  /// load succeeds. Another day's data is never shown under [_date].
  DateTime? _loadedDate;
  late Future<CoachDecision?> _decision;

  /// The meal photo notice as last loaded, for the Log a meal sheet's
  /// "Turn off meal photo AI". Null until it loads, and on the fixture.
  PhotoAiNotice? _mealPhotoNotice;

  @override
  void initState() {
    super.initState();
    _decision = widget.coach.loadLatest();
    _refresh();
    _loadMealPhotoNotice();
    widget.planChanges?.addListener(_planChanged);
    _resume.attach();
  }

  @override
  void dispose() {
    _resume.detach();
    widget.planChanges?.removeListener(_planChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(NutritionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _reloadIfStale(within: _reselectAfter);
    }
  }

  /// A tab opened again reloads data older than this.
  static const _reselectAfter = Duration(minutes: 1);

  /// Coming back to the app or to this tab. Past midnight the screen moves to
  /// the new today unless the athlete picked another day, so a meal logged in
  /// the morning is filed under the morning's date. Data that is old, or
  /// belongs to another day than the one shown, is loaded again.
  void _reloadIfStale({Duration? within}) {
    if (!mounted) return;
    final now = widget.clock();
    if (!_pickedDate && !isSameLocalDay(_date, now)) {
      setState(() {
        _date = now;
        _decision = widget.coach.loadLatest();
      });
      unawaited(_refresh());
      return;
    }
    if (_loaded.isStale(today: localDayKey(_date), within: within)) {
      setState(() {
        _decision = widget.coach.loadLatest();
      });
      unawaited(_refresh());
    }
  }

  void _planChanged() {
    if (mounted) unawaited(_refresh());
  }

  Future<void> _loadMealPhotoNotice() async {
    final repository = widget.repository;
    if (repository is! MealPhotoRepository) return;
    try {
      final notice = await (repository as MealPhotoRepository)
          .loadMealPhotoNotice();
      if (mounted) setState(() => _mealPhotoNotice = notice);
    } catch (e) {
      // The sheet then offers no off switch; the photo flow loads it again.
      logNonCritical(e);
    }
  }

  /// Records a withdrawal: the server stops sending meal photos at once, and
  /// the next photo shows the notice again.
  Future<void> _turnOffMealPhotoAi() async {
    final repository = widget.repository;
    final notice = _mealPhotoNotice;
    if (repository is! MealPhotoRepository || notice == null) return;
    try {
      await (repository as MealPhotoRepository).recordMealPhotoConsent(
        noticeVersion: notice.version,
        granted: false,
      );
    } catch (error, stackTrace) {
      logNonCritical(error);
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      if (mounted) {
        TracendToast.show(
          context,
          'Meal photo AI is still on. Check the connection and try again.',
          icon: CupertinoIcons.exclamationmark_circle,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _mealPhotoNotice = notice.withGranted(false));
    TracendToast.show(
      context,
      'Meal photo AI is off. Photos are no longer sent.',
      icon: CupertinoIcons.checkmark_alt,
    );
  }

  Future<void> _refresh() async {
    // The day this load is for. If the athlete moves to another day, or a
    // newer load starts, before the reply arrives, the reply is dropped: it
    // must never show one day's meals under another day's date.
    final requested = _date;
    final load = ++_loads;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.repository.loadTargets(),
        widget.repository.loadSummary(requested),
        widget.repository.loadMeals(requested),
        if (widget.repository is NutritionScheduleRepository)
          (widget.repository as NutritionScheduleRepository).loadSchedule(
            requested,
          )
        else
          Future.value(
            const NutritionSchedule(title: 'Meal schedule', items: []),
          ),
      ]);
      if (!mounted || load != _loads) return;
      _loaded.mark(day: localDayKey(requested));
      setState(() {
        _targets = values[0] as NutritionTargets?;
        _summary = values[1] as NutritionSummary;
        _meals = values[2] as List<MealEntry>;
        _schedule = values[3] as NutritionSchedule;
        _loadedDate = requested;
      });
    } catch (e) {
      logNonCritical(e);
      if (mounted && load == _loads) {
        setState(
          () => _error = 'Nutrition data is unavailable. Pull to retry.',
        );
      }
    } finally {
      if (mounted && load == _loads) setState(() => _loading = false);
    }
  }

  Future<void> _selectDate(DateTime candidate) async {
    final today = widget.clock();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (candidate.isAfter(todayOnly)) return;
    if (isSameLocalDay(candidate, _date)) return;
    setState(() {
      _date = candidate;
      _pickedDate = !isSameLocalDay(candidate, today);
    });
    await _refresh();
  }

  /// Pull to refresh: the day's data and the coach's latest guidance.
  Future<void> _pullToRefresh() async {
    setState(() {
      _decision = widget.coach.loadLatest();
    });
    await _refresh();
  }

  bool get _showsLoadedDay {
    final loaded = _loadedDate;
    return loaded != null &&
        loaded.year == _date.year &&
        loaded.month == _date.month &&
        loaded.day == _date.day;
  }

  bool get _isToday {
    return isSameLocalDay(_date, widget.clock());
  }

  bool get _isCurrentWeek => mondayOf(_date) == mondayOf(widget.clock());

  String get _dateLabel => friendlyDate(_date);

  Future<void> _openManualMeal({ScheduledMeal? scheduled, String? mealType}) =>
      showTracendSheet<void>(
        context,
        title: 'Enter meal',
        subtitle: 'It counts toward your totals as soon as you confirm it.',
        scrollable: false,
        builder: (_) => ManualMealSheet(
          initialMealType: mealType ?? defaultMealType(DateTime.now()),
          onSave: (input) => _saveManualMeal(scheduled, input),
        ),
      );

  /// Saves a meal from the manual sheet, which stays open with what was typed
  /// if this throws. When the save fails the server is asked whether it wrote
  /// the meal anyway (a lost reply): if it did, the meal counts as saved; if
  /// the answer is no, the failure stands; if it cannot be told,
  /// [MealSaveOutcomeUnknown] says so. The day is reloaded after any failure,
  /// and a retry carries the same key, so it adds nothing twice.
  Future<void> _saveManualMeal(
    ScheduledMeal? scheduled,
    ManualMealResult input,
  ) async {
    final repository = widget.repository;
    try {
      if (scheduled != null && repository is ScheduledMealLogger) {
        await (repository as ScheduledMealLogger).saveScheduledMeal(
          date: _date,
          scheduleItemId: scheduled.id,
          mealType: input.mealType,
          food: input.food,
          idempotencyKey: input.idempotencyKey,
        );
      } else {
        await repository.saveManualMeal(
          date: _date,
          mealType: input.mealType,
          food: input.food,
          idempotencyKey: input.idempotencyKey,
        );
      }
    } catch (e) {
      logNonCritical(e);
      final bool written;
      try {
        written = await repository.isMealSaved(input.idempotencyKey);
      } catch (lookup) {
        logNonCritical(lookup);
        if (mounted) unawaited(_refresh());
        throw const MealSaveOutcomeUnknown();
      }
      if (!written) {
        if (mounted) unawaited(_refresh());
        rethrow;
      }
    }
    unawaited(TracendHaptics.success());
    if (!mounted) return;
    TracendToast.show(
      context,
      'Meal logged',
      icon: CupertinoIcons.checkmark_alt,
    );
    unawaited(_refresh());
  }

  Future<void> _reviewFixture(String mealType) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final mealId = await widget.repository.createFixtureMeal(
        date: _date,
        mealType: mealType,
      );
      await _openCandidateReview(mealId);
    } catch (e) {
      logNonCritical(e);
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

  Future<void> _selectMealPhoto(ImageSource source, String mealType) async {
    final repository = widget.repository;
    if (repository is! MealPhotoRepository) return;
    setState(() {
      _photoError = null;
      _photoDiagnostic = null;
    });
    if (!await _mealPhotoNoticeGranted(repository as MealPhotoRepository)) {
      return;
    }
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
        mealType: mealType,
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

  /// Shows the meal photo notice until its current version is granted, and
  /// says whether it now is. No photo is picked or sent before that.
  Future<bool> _mealPhotoNoticeGranted(MealPhotoRepository repository) async {
    final PhotoAiNotice notice;
    try {
      notice = await repository.loadMealPhotoNotice();
    } catch (error, stackTrace) {
      _photoFailed(
        MealPhotoFailure('notice', error.runtimeType.toString()),
        stackTrace,
      );
      return false;
    }
    if (mounted) setState(() => _mealPhotoNotice = notice);
    if (notice.granted) return true;
    if (!mounted) return false;
    final agreed = await showTracendSheet<bool>(
      context,
      builder: (_) =>
          _MealPhotoNoticeSheet(notice: notice, repository: repository),
    );
    if (agreed != true || !mounted) return false;
    setState(() => _mealPhotoNotice = notice.withGranted(true));
    return true;
  }

  void _photoFailed(MealPhotoFailure failure, StackTrace stackTrace) {
    logNonCritical(failure, 'Meal photo failed');
    unawaited(Sentry.captureException(failure, stackTrace: stackTrace));
    if (mounted) {
      setState(() {
        _photoError = mealPhotoFailureMessage(failure);
        _photoDiagnostic = mealPhotoFailureDiagnostic(failure);
      });
    }
  }

  /// A draft the app did not just analyze is known to have no estimates for
  /// good only after the analysis could have finished: a draft younger than
  /// [mealAnalysisWindow] may still be running.
  bool _analysisSettled(MealEntry meal) {
    final created = meal.loggedAt;
    return created != null &&
        DateTime.now().difference(created) >= mealAnalysisWindow;
  }

  /// [analysisSettled] says the draft's analysis is over: true for the one
  /// just run here, and for an older draft ([_analysisSettled]).
  Future<void> _openCandidateReview(
    String mealId, {
    bool fromPhoto = false,
    bool analysisSettled = true,
  }) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final candidates = await widget.repository.loadCandidates(mealId);
      if (!mounted) return;
      setState(() => _working = false);
      final selected = await showTracendSheet<List<MealCandidate>>(
        context,
        title: 'Review candidates',
        scrollable: false,
        builder: (_) => CandidateSheet(
          candidates: candidates,
          canDiscard: analysisSettled,
          onDiscard: () => _discardDraft(mealId),
        ),
      );
      if (selected == null || selected.isEmpty) return;
      await _run(
        () => widget.repository.confirmCandidates(mealId, selected),
        successMessage: 'Meal logged',
      );
    } catch (e) {
      logNonCritical(e);
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

  /// Saves through [action], then reloads the day. A confirmed meal plays
  /// the `success` haptic; [successMessage] shows as a toast.
  Future<void> _run(
    Future<void> Function() action, {
    required String successMessage,
    bool confirmsMeal = true,
    String failureMessage =
        'Meal was not saved. Your confirmed totals are unchanged.',
  }) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      if (confirmsMeal) unawaited(TracendHaptics.success());
      if (mounted) {
        TracendToast.show(
          context,
          successMessage,
          icon: confirmsMeal
              ? CupertinoIcons.checkmark_alt
              : CupertinoIcons.delete,
        );
      }
      await _refresh();
    } catch (e) {
      logNonCritical(e);
      if (mounted) {
        setState(() => _error = failureMessage);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Deletes a draft meal that has nothing to review, then reloads the day.
  Future<void> _discardDraft(String mealId) async {
    await widget.repository.deleteMeal(mealId);
    if (!mounted) return;
    TracendToast.show(context, 'Draft deleted', icon: CupertinoIcons.delete);
    unawaited(_refresh());
  }

  Future<void> _deleteMeal(MealEntry meal) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this meal?',
      message:
          'The meal and its nutrition values will be removed from the day’s '
          'totals. This action is recorded for account security.',
      confirmLabel: 'Delete meal',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => widget.repository.deleteMeal(meal.id),
      successMessage: 'Meal deleted',
      confirmsMeal: false,
      failureMessage:
          'Meal was not deleted. Your confirmed totals are unchanged.',
    );
  }

  Future<void> _openLogMeal() async {
    final photos = widget.repository is MealPhotoRepository;
    final choice = await showTracendSheet<LogMealChoice>(
      context,
      title: 'Log a meal',
      builder: (_) => LogMealSheet(
        initialMealType: defaultMealType(widget.clock()),
        photosAvailable: photos,
        photoAiGranted: _mealPhotoNotice?.granted ?? false,
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice.method) {
      case LogMealMethod.camera:
        await _selectMealPhoto(ImageSource.camera, choice.mealType);
      case LogMealMethod.library:
        await _selectMealPhoto(ImageSource.gallery, choice.mealType);
      case LogMealMethod.manual:
        await _openManualMeal(mealType: choice.mealType);
      case LogMealMethod.sample:
        await _reviewFixture(choice.mealType);
      case LogMealMethod.turnOffPhotoAi:
        await _turnOffMealPhotoAi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final showData = _showsLoadedDay;
    final nextMeal = _isToday && showData ? _schedule?.nextMeal : null;
    final today = widget.clock();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final timeline = buildNutritionTimeline(
      _schedule?.items ?? const [],
      _meals,
    );
    return TracendScrollView(
      title: 'Nutrition',
      subtitle: _dateLabel,
      onRefresh: _pullToRefresh,
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
        if (_error != null) ...[
          _NoticeCard(message: _error!),
          const SizedBox(height: TracendSpacing.xs),
        ],
        if (!showData && _loading)
          const _NutritionSkeleton()
        else if (showData) ...[
          if (nextMeal != null) ...[
            MicroMotionEntrance(
              child: _NextMealCard(
                meal: nextMeal,
                onLog: _working
                    ? null
                    : () => _openManualMeal(scheduled: nextMeal),
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
          ],
          MicroMotionEntrance(
            delay: MicroMotion.stagger(1),
            child: TargetsGrid(summary: _summary, targets: _targets),
          ),
          SectionLabel(_isToday ? 'Today’s meals' : 'Meals'),
          NutritionTimeline(
            entries: timeline,
            enabled: !_working,
            onReview: (meal) => _openCandidateReview(
              meal.id,
              analysisSettled: _analysisSettled(meal),
            ),
            onDelete: _deleteMeal,
            onLog: (slot) => _openManualMeal(scheduled: slot),
          ),
        ],
        const SizedBox(height: TracendSpacing.sm),
        SizedBox(
          width: double.infinity,
          // The next-meal card owns the screen's primary action when shown.
          child: nextMeal == null
              ? FilledButton(
                  key: const ValueKey('log-a-meal'),
                  onPressed: _working ? null : _openLogMeal,
                  child: _LogMealLabel(working: _working && !_analyzingPhoto),
                )
              : OutlinedButton(
                  key: const ValueKey('log-a-meal'),
                  onPressed: _working ? null : _openLogMeal,
                  child: _LogMealLabel(working: _working && !_analyzingPhoto),
                ),
        ),
        if (_analyzingPhoto) ...[
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              const ExcludeSemantics(child: TracendLoader(size: 22)),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Text('Analyzing meal photo…', style: theme.bodyMedium),
              ),
            ],
          ),
        ],
        if (_photoError != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          _NoticeCard(message: _photoError!, diagnostic: _photoDiagnostic),
        ],
        FutureBuilder<CoachDecision?>(
          future: _decision,
          builder: (context, snapshot) {
            final decision = snapshot.data;
            if (decision == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.lg),
              child: NutritionInsightCard(decision: decision),
            );
          },
        ),
      ],
    );
  }
}

/// The schedule's next meal: its time and status, the planned foods, and
/// the screen's primary action, **Log meal**.
class _NextMealCard extends StatelessWidget {
  const _NextMealCard({required this.meal, required this.onLog});

  final ScheduledMeal meal;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final due = meal.status == 'due';
    return PremiumGradientCard(
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(
            label: '${due ? 'Due now' : 'Next meal'} · ${meal.time}',
            icon: CupertinoIcons.clock_fill,
            tone: due ? StatusTone.caution : StatusTone.neutral,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(meal.label, style: theme.headlineMedium),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            meal.foods
                .map((food) => '${food['name']} · ${food['quantity']}')
                .join('\n'),
            style: theme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onLog,
              icon: const Icon(CupertinoIcons.check_mark_circled_solid),
              label: const Text('Log meal'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for the totals card and the meal list while a day loads.
class _NutritionSkeleton extends StatelessWidget {
  const _NutritionSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading nutrition',
    container: true,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TracendSkeleton.block(height: 236),
        SizedBox(height: TracendSpacing.lg),
        TracendSkeleton.line(widthFactor: 0.4, height: 20),
        SizedBox(height: TracendSpacing.sm),
        TracendSkeleton.block(height: 168),
      ],
    ),
  );
}

class _LogMealLabel extends StatelessWidget {
  const _LogMealLabel({required this.working});
  final bool working;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      working
          ? const ExcludeSemantics(child: TracendLoader(size: 20))
          : const Icon(CupertinoIcons.plus, size: 18),
      const SizedBox(width: TracendSpacing.xs),
      const Flexible(child: Text('Log a meal')),
    ],
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, this.diagnostic});

  final String message;

  /// Beta diagnostic, shown smaller under the message.
  final String? diagnostic;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: colors.stateAttention,
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (diagnostic != null) ...[
                  const SizedBox(height: TracendSpacing.xxs),
                  SelectableText(
                    diagnostic!,
                    style: TracendTheme.dataUtility(
                      colors,
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The meal photo notice and the choice. Agreeing records the grant before
/// the sheet closes with true; "Not now" closes it with false.
class _MealPhotoNoticeSheet extends StatefulWidget {
  const _MealPhotoNoticeSheet({required this.notice, required this.repository});

  final PhotoAiNotice notice;
  final MealPhotoRepository repository;

  @override
  State<_MealPhotoNoticeSheet> createState() => _MealPhotoNoticeSheetState();
}

class _MealPhotoNoticeSheetState extends State<_MealPhotoNoticeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.recordMealPhotoConsent(
        noticeVersion: widget.notice.version,
        granted: true,
      );
    } catch (e) {
      logNonCritical(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Your choice was not saved. Check the connection and try again.';
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: TracendSpacing.xs),
    child: AiNoticePanel(
      title: 'Analyze meal photos with AI?',
      notice: widget.notice,
      agreeLabel: 'Agree and continue',
      busy: _busy,
      error: _error,
      onAgree: _agree,
      onDecline: () => Navigator.of(context).pop(false),
    ),
  );
}
