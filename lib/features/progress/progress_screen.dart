import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/widgets/measurement_widgets.dart';
import 'package:tracend/features/progress/widgets/photo_widgets.dart';
import 'package:tracend/features/progress/widgets/physique_check_widgets.dart';
import 'package:tracend/features/progress/widgets/training_evidence_widgets.dart';
import 'package:tracend/features/progress/widgets/weekly_review_widgets.dart';
import 'package:tracend/features/progress/widgets/weight_trend_card.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Period options; the selection covers weigh-ins and workouts alike.
const progressPeriods = <(int, String)>[(28, '4W'), (84, '12W'), (182, '6M')];

/// Recent weigh-ins shown before "See all".
const _recentWeighIns = 3;

/// What the capture sheet says when iOS could not hand over a photo.
String progressPhotoPickMessage(String code) => switch (code) {
  'camera_access_denied' =>
    'Tracend cannot use the camera. Allow it in Settings › Tracend › Camera, or choose a photo from your library.',
  'photo_access_denied' =>
    'Tracend cannot open your photos. Allow it in Settings › Tracend › Photos.',
  // Usually a photo kept only in iCloud that did not download.
  'invalid_image' =>
    'This photo could not be loaded from your library. If it is stored in iCloud, try again on Wi-Fi, or take a photo instead.',
  _ => 'This photo could not be opened. Try again, or take a photo instead.',
};

/// Opens the camera or library for one pose; null when the user cancels.
typedef ProgressPhotoPicker = Future<XFile?> Function(ImageSource source);

Future<XFile?> _pickWithImagePicker(ImageSource source) =>
    ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
      requestFullMetadata: false,
    );

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    required this.repository,
    this.training,
    this.brief,
    this.physique = const FixturePhysiqueCheckRepository(),
    this.now = DateTime.now,
    this.pickPhoto = _pickWithImagePicker,
    super.key,
  });
  final ProgressRepository repository;
  final TrainingHubRepository? training;
  final DailyBriefRepository? brief;
  final PhysiqueCheckRepository physique;

  /// Clock for the period window and relative dates.
  final DateTime Function() now;
  final ProgressPhotoPicker pickPhoto;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

typedef _ProgressData = ({
  List<BodyMeasurement> measurements,
  ProgressSummary summary,
  List<ProgressPhotoSet> photoSets,
  WeeklyProgressReview? weeklyReview,
  WeeklyReviewJob? weeklyReviewJob,
  TrainingHubData? training,
  Set<String> newBests,
});

/// Whether this account may run physique checks, and its newest result.
typedef _PhysiqueState = ({String? provider, PhysiqueAnalysis? latest});

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<_ProgressData> _future;
  int _periodDays = 84;
  String? _activeSet;
  final Set<String> _capturedPoses = {};
  bool _hasConsent = false;
  late final Future<DailyBrief> _brief;
  late final Future<String?> _goal;
  late Future<_PhysiqueState> _physique;

  /// A failed action, shown next to where it was started until dismissed or
  /// the next action starts. Toasts only confirm what succeeded; an error is
  /// never only a toast.
  String? _problem;
  _ProblemArea _problemArea = _ProblemArea.top;

  @override
  void initState() {
    super.initState();
    _reload();
    _physique = _loadPhysique();
    _brief = (widget.brief ?? const FixtureDailyBriefRepository()).load(
      widget.now(),
    );
    final repository = widget.repository;
    _goal = repository is ProgressGoalRepository
        ? (repository as ProgressGoalRepository).loadActiveGoal().catchError(
            (Object _) => null,
          )
        : Future<String?>.value();
  }

  void _reload() {
    _future =
        Future.wait([
          widget.repository.loadMeasurements(),
          widget.repository.loadSummary(),
          widget.repository.loadPhotoSets(),
          widget.repository.loadLatestWeeklyReview(),
          widget.repository.loadLatestWeeklyReviewJob(),
          widget.training?.loadTrainingHub(periodDays: _periodDays) ??
              Future<TrainingHubData?>.value(),
        ]).then((v) async {
          final training = v[5] as TrainingHubData?;
          return (
            measurements: v[0] as List<BodyMeasurement>,
            summary: v[1] as ProgressSummary,
            photoSets: v[2] as List<ProgressPhotoSet>,
            weeklyReview: v[3] as WeeklyProgressReview?,
            weeklyReviewJob: v[4] as WeeklyReviewJob?,
            training: training,
            newBests: await _loadNewBests(training),
          );
        });
  }

  /// Lifts whose latest workout set their all-time best, from
  /// `get_my_exercise_history`. Without that history no tile says "New best".
  Future<Set<String>> _loadNewBests(TrainingHubData? hub) async {
    final repository = widget.training;
    if (hub == null || hub.progression.isEmpty) return const {};
    if (repository is! WorkoutRepository) return const {};
    final keys = liftHistoryKeys(hub);
    try {
      final history = await (repository as WorkoutRepository)
          .loadExerciseHistory(keys.values.toList());
      return liftNewBests(hub, keys, history);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return const {};
    }
  }

  Future<void> _pullToRefresh() async {
    setState(() {
      _problem = null;
      _reload();
      _physique = _loadPhysique();
    });
    // A failed reload shows the error card; the refresh only waits for it.
    await _future.then<void>((_) {}, onError: (Object _) {});
  }

  void _showProblem(String message, _ProblemArea area) => setState(() {
    _problem = message;
    _problemArea = area;
  });

  /// The problem card when the latest failure belongs to [area].
  List<Widget> _problemIn(_ProblemArea area, {bool below = false}) {
    final problem = _problem;
    if (problem == null || _problemArea != area) return const [];
    final card = _ProblemCard(
      message: problem,
      onDismiss: () => setState(() => _problem = null),
    );
    const gap = SizedBox(height: TracendSpacing.xs);
    return below ? [gap, card] : [card, gap];
  }

  /// Whether a check can run now, and the newest stored check. They load
  /// apart: a check run earlier stays visible, and disclosed, after the
  /// feature is switched off for this account.
  Future<_PhysiqueState> _loadPhysique() async {
    final provider = widget.physique.loadProvider();
    PhysiqueAnalysis? latest;
    try {
      latest = await widget.physique.loadLatestAnalysis();
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
    return (provider: await provider, latest: latest);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _future,
    builder: (context, snapshot) {
      final colors = context.tracendColors;
      final data = snapshot.data;
      final loading = snapshot.connectionState == ConnectionState.waiting;
      return TracendScrollView(
        title: 'Progress',
        subtitle: 'Your body and strength over time',
        onRefresh: _pullToRefresh,
        trailing: IconButton.filledTonal(
          key: const ValueKey('record-measurement-header'),
          onPressed: _record,
          tooltip: 'Record measurement',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          style: IconButton.styleFrom(
            backgroundColor: colors.surface,
            foregroundColor: colors.textPrimary,
          ),
          icon: const Icon(CupertinoIcons.plus),
        ),
        children: [
          TracendSegmentedControl<int>(
            segments: progressPeriods,
            selected: _periodDays,
            onChanged: (days) => setState(() {
              _periodDays = days;
              _reload();
            }),
          ),
          const SizedBox(height: TracendSpacing.md),
          ..._problemIn(_ProblemArea.top),
          if (data != null)
            // A period change keeps the last answer on screen, dimmed,
            // until the new one arrives.
            for (final section in _content(data))
              AnimatedOpacity(
                opacity: loading ? 0.5 : 1,
                duration: TracendMotionScope.fade(context, TracendMotion.quick),
                child: section,
              )
          else if (snapshot.hasError)
            _ErrorCard(onRetry: () => setState(_reload))
          else
            const _ProgressSkeleton(),
        ],
      );
    },
  );

  List<Widget> _content(_ProgressData data) {
    final now = widget.now();
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: _periodDays - 1));
    final periodMeasurements = data.measurements
        .where((m) => !m.date.isBefore(windowStart))
        .toList();
    final sections = <Widget>[
      FutureBuilder<DailyBrief>(
        future: _brief,
        builder: (context, brief) => FutureBuilder<String?>(
          future: _goal,
          builder: (context, goal) => WeightHeroCard(
            measurements: data.measurements,
            periodMeasurements: periodMeasurements,
            computed: brief.data?.computed,
            goal: goal.data,
            fallbackWeightKg: data.summary.currentWeightKg,
            onRecord: _record,
            now: now,
          ),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('This week'),
          WeeklyReviewActionCard(
            weeklyReview: data.weeklyReview,
            weeklyReviewJob: data.weeklyReviewJob,
            now: now,
            onTap: data.weeklyReview != null
                ? () => _openWeeklyReview(data.weeklyReview!)
                : data.weeklyReviewJob?.isPending == true
                ? () => setState(_reload)
                : _requestWeeklyReview,
          ),
          ..._problemIn(_ProblemArea.weeklyReview, below: true),
        ],
      ),
      if (data.measurements.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              'Recent weigh-ins',
              actionLabel: data.measurements.length > _recentWeighIns
                  ? 'See all'
                  : null,
              onAction: () => _openAllWeighIns(data.measurements),
            ),
            WeighInList(
              measurements: data.measurements,
              limit: _recentWeighIns,
              onOpen: _openMeasurementDetail,
              now: now,
            ),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Strength'),
          TrainingEvidenceSection(
            training: data.training,
            periodDays: _periodDays,
            newBests: data.newBests,
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Progress photos'),
          FutureBuilder<_PhysiqueState>(
            future: _physique,
            builder: (context, physique) {
              final provider = physique.data?.provider;
              final newest = data.photoSets.isEmpty
                  ? null
                  : data.photoSets.first;
              return PhotoProgressCard(
                photoSets: data.photoSets,
                inProgress: _activeSet != null && _capturedPoses.isNotEmpty,
                onCapture: _openPhotoCapture,
                onOpenSets: () => _openPhotoSets(data.photoSets),
                photoCheckProvider: provider,
                onPhysiqueCheck:
                    provider != null && newest?.status == 'complete'
                    ? () => _openPhysiqueCheck(photoSetId: newest!.id)
                    : null,
                latestPhysique: physique.data?.latest,
                onOpenPhysique: (analysis) =>
                    _openPhysiqueCheck(analysis: analysis),
                now: now,
              );
            },
          ),
          ..._problemIn(_ProblemArea.photos, below: true),
        ],
      ),
    ];
    // Only the first screenful enters with motion; sections built later by
    // scrolling appear at once instead of waiting out a stagger delay.
    return [
      for (var i = 0; i < sections.length; i++)
        i < 2
            ? MicroMotionEntrance(
                delay: MicroMotion.stagger(i),
                child: sections[i],
              )
            : sections[i],
    ];
  }

  Future<void> _openMeasurementDetail(BodyMeasurement measurement) async {
    final now = widget.now();
    await showTracendSheet<void>(
      context,
      title: friendlyDate(measurement.date, now: now),
      subtitle: measurementSourceLabel(measurement.source),
      builder: (_) => MeasurementDetailSheet(measurement: measurement),
    );
  }

  Future<void> _openAllWeighIns(List<BodyMeasurement> measurements) async {
    await showTracendSheet<void>(
      context,
      title: 'All weigh-ins',
      subtitle: '${measurements.length} recorded',
      detents: const [0.7, 0.95],
      builder: (_) => WeighInList(
        measurements: measurements,
        onOpen: _openMeasurementDetail,
        now: widget.now(),
      ),
    );
  }

  Future<void> _requestWeeklyReview() async {
    setState(() => _problem = null);
    try {
      await widget.repository.requestWeeklyReview();
      if (!mounted) return;
      setState(_reload);
      TracendToast.show(
        context,
        'Preparing your weekly review. Check back soon.',
        icon: CupertinoIcons.hourglass,
      );
    } on ProgressSessionException {
      if (!mounted) return;
      _showProblem(
        'Your session expired. Sign out, then sign in again.',
        _ProblemArea.weeklyReview,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      _showProblem(
        'Could not start the weekly review. Try again.',
        _ProblemArea.weeklyReview,
      );
    }
  }

  Future<void> _openWeeklyReview(WeeklyProgressReview review) async {
    final acknowledge = await showTracendSheet<bool>(
      context,
      title: 'Weekly review',
      subtitle: 'Week of ${shortDate(review.week, now: widget.now())}',
      detents: const [0.85, 0.95],
      builder: (_) => WeeklyReviewSheet(review: review),
    );
    if (acknowledge != true || review.acknowledged) return;
    await widget.repository.acknowledgeWeeklyReview(review.id);
    if (mounted) setState(_reload);
  }

  Future<void> _record() async {
    final result = await showTracendSheet<BodyMeasurement>(
      context,
      title: 'Record measurement',
      scrollable: false,
      builder: (_) => const MeasurementEntrySheet(),
    );
    if (result == null || !mounted) return;
    setState(() => _problem = null);
    try {
      await widget.repository.saveMeasurement(result);
      if (!mounted) return;
      setState(_reload);
      unawaited(TracendHaptics.success());
      TracendToast.show(context, 'Weigh-in saved');
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      _showProblem(
        'Could not save measurement. Check your connection and try again.',
        _ProblemArea.top,
      );
    }
  }

  Future<void> _ensureConsent() async {
    if (_hasConsent) return;
    final accepted = await showTracendConfirm(
      context,
      title: 'Save private progress photos?',
      message:
          'Your photos are stored privately and only you can open them. '
          'They are never sent to an AI model.',
      confirmLabel: 'I agree and continue',
    );
    if (!accepted || !mounted) return;
    try {
      await widget.repository.grantPhotoStorageConsent();
      _hasConsent = true;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        _showProblem('Could not save consent. Try again.', _ProblemArea.photos);
      }
    }
  }

  Future<void> _openPhotoCapture() async {
    setState(() => _problem = null);
    await _ensureConsent();
    if (!_hasConsent || !mounted) return;
    await showTracendSheet<void>(
      context,
      title: 'Progress photos',
      builder: (_) => PhotoCaptureSheet(
        captured: _activeSet == null ? const {} : {..._capturedPoses},
        onCapture: _capturePose,
      ),
    );
    if (mounted) setState(_reload);
  }

  /// Uploads one pose into the open set for the capture sheet.
  Future<({bool captured, String? error})> _capturePose(
    String pose,
    ImageSource source,
  ) async {
    // The photo is chosen before a set is opened, so a cancelled or failed
    // pick never leaves an empty set behind.
    final XFile? photo;
    try {
      photo = await widget.pickPhoto(source);
    } on PlatformException catch (e) {
      debugPrint('Progress photo pick failed: ${e.code}');
      return (captured: false, error: progressPhotoPickMessage(e.code));
    }
    if (photo == null) return (captured: false, error: null);
    try {
      _activeSet ??= await widget.repository.beginPhotoSet();
      await widget.repository.uploadPhoto(
        setId: _activeSet!,
        pose: pose,
        bytes: await photo.readAsBytes(),
        contentType: 'image/jpeg',
      );
      _capturedPoses.add(pose);
      if (_capturedPoses.length == progressPhotoPoses.length) {
        _activeSet = null;
        _capturedPoses.clear();
      }
      return (captured: true, error: null);
    } catch (e, stackTrace) {
      // Keep the open set and its finished poses: the capture sheet still
      // shows them, so a retry must upload into the same set rather than
      // start a second, partial one.
      debugPrint('Non-critical error: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      return (
        captured: false,
        error: 'Photo was not saved. Try again when ready.',
      );
    }
  }

  /// Starts a check on [photoSetId], or opens the stored [analysis].
  Future<void> _openPhysiqueCheck({
    String? photoSetId,
    PhysiqueAnalysis? analysis,
  }) async {
    // The sheet's title changes with the check's phase, so it draws its own.
    await showTracendSheet<void>(
      context,
      scrollable: false,
      builder: (_) => PhysiqueCheckSheet(
        repository: widget.physique,
        photoSetId: photoSetId,
        analysis: analysis,
      ),
    );
    if (!mounted) return;
    setState(() {
      _physique = _loadPhysique();
    });
  }

  Future<void> _openPhotoSets(List<ProgressPhotoSet> sets) async {
    await showTracendSheet<void>(
      context,
      title: 'Past photo sets',
      builder: (sheetContext) => PhotoSetsSheet(
        photoSets: sets,
        now: widget.now(),
        onView: _viewSet,
        onDelete: (set) {
          Navigator.pop(sheetContext);
          _deleteSet(set);
        },
      ),
    );
  }

  Future<void> _viewSet(ProgressPhotoSet set) async {
    setState(() => _problem = null);
    try {
      final urls = await widget.repository.createPhotoReadUrls(set);
      if (!mounted) return;
      await showTracendSheet<void>(
        context,
        title: 'Private photo set',
        subtitle: 'Only you can open these. The link expires in a minute.',
        builder: (_) => PrivatePhotoViewer(urls: urls),
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        _showProblem(
          'Could not open private photos. Try again.',
          _ProblemArea.photos,
        );
      }
    }
  }

  Future<void> _deleteSet(ProgressPhotoSet set) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this photo set?',
      message: 'The photos will be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete set',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _problem = null);
    try {
      await widget.repository.deletePhotoSet(set);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        _showProblem(
          'Could not delete the photo set. Try again.',
          _ProblemArea.photos,
        );
      }
      return;
    }
    if (!mounted) return;
    TracendToast.show(
      context,
      'Photo set deleted',
      icon: CupertinoIcons.delete,
    );
    // The set's physique checks were deleted with it.
    setState(() {
      _reload();
      _physique = _loadPhysique();
    });
  }
}

/// Where a failed action's message shows: beside the control that started
/// it, so it is in view.
enum _ProblemArea { top, weeklyReview, photos }

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => PremiumGradientCard(
    child: Row(
      children: [
        Icon(
          CupertinoIcons.wifi_exclamationmark,
          color: context.tracendColors.stateAttention,
        ),
        const SizedBox(width: TracendSpacing.sm),
        const Expanded(
          child: Text('Progress could not load. Check your connection.'),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

/// A failed action, in words, with a way to put it away.
class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      liveRegion: true,
      child: PremiumGradientCard(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.md,
          TracendSpacing.xxs,
          TracendSpacing.xxs,
          TracendSpacing.xxs,
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 20,
              color: colors.stateAttention,
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: TracendSpacing.sm,
                ),
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              icon: Icon(
                CupertinoIcons.xmark,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the hero and the first sections on the first load.
class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading Progress',
    container: true,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TracendSkeleton.block(height: 300),
        SizedBox(height: TracendSpacing.lg),
        TracendSkeleton.line(widthFactor: 0.35, height: 20),
        SizedBox(height: TracendSpacing.sm),
        TracendSkeleton.block(height: 132),
        SizedBox(height: TracendSpacing.lg),
        TracendSkeleton.line(widthFactor: 0.5, height: 20),
        SizedBox(height: TracendSpacing.sm),
        TracendSkeleton.block(height: 180),
      ],
    ),
  );
}
