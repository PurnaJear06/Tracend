import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/widgets/measurement_widgets.dart';
import 'package:tracend/features/progress/widgets/photo_widgets.dart';
import 'package:tracend/features/progress/widgets/training_evidence_widgets.dart';
import 'package:tracend/features/progress/widgets/weekly_review_widgets.dart';
import 'package:tracend/features/progress/widgets/weight_trend_card.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// Period options; the selection covers weigh-ins and workouts alike.
const progressPeriods = <(int, String)>[(28, '4W'), (84, '12W'), (182, '6M')];

/// Recent weigh-ins shown before "See all".
const _recentWeighIns = 3;

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    required this.repository,
    this.training,
    this.brief,
    this.now = DateTime.now,
    super.key,
  });
  final ProgressRepository repository;
  final TrainingHubRepository? training;
  final DailyBriefRepository? brief;

  /// Clock for the period window and relative dates.
  final DateTime Function() now;
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
});

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<_ProgressData> _future;
  int _periodDays = 84;
  String? _activeSet;
  final Set<String> _capturedPoses = {};
  bool _hasConsent = false;
  late final Future<DailyBrief> _brief;
  late final Future<String?> _goal;

  @override
  void initState() {
    super.initState();
    _reload();
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
        ]).then(
          (v) => (
            measurements: v[0] as List<BodyMeasurement>,
            summary: v[1] as ProgressSummary,
            photoSets: v[2] as List<ProgressPhotoSet>,
            weeklyReview: v[3] as WeeklyProgressReview?,
            weeklyReviewJob: v[4] as WeeklyReviewJob?,
            training: v[5] as TrainingHubData?,
          ),
        );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final loading = snapshot.connectionState == ConnectionState.waiting;
      return TracendScrollView(
        title: 'Progress',
        subtitle: 'Your body and strength over time',
        trailing: IconButton.filledTonal(
          key: const ValueKey('record-measurement-header'),
          onPressed: _record,
          tooltip: 'Record measurement',
          style: IconButton.styleFrom(
            backgroundColor: context.tracendColors.actionPrimary.withValues(
              alpha: 0.16,
            ),
            foregroundColor: context.tracendColors.actionPrimary,
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
          SizedBox(
            height: TracendSpacing.md,
            child: loading
                ? const Center(child: LinearProgressIndicator(minHeight: 2))
                : null,
          ),
          if (data != null)
            ..._content(data)
          else if (snapshot.hasError)
            _ErrorCard(onRetry: () => setState(_reload)),
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
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Progress photos'),
          PhotoProgressCard(
            photoSets: data.photoSets,
            inProgress: _activeSet != null && _capturedPoses.isNotEmpty,
            onCapture: _openPhotoCapture,
            onOpenSets: () => _openPhotoSets(data.photoSets),
            now: now,
          ),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          MeasurementDetailSheet(measurement: measurement, now: widget.now()),
    );
  }

  Future<void> _openAllWeighIns(List<BodyMeasurement> measurements) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => WeighInHistorySheet(
        measurements: measurements,
        onOpen: _openMeasurementDetail,
        now: widget.now(),
      ),
    );
  }

  Future<void> _requestWeeklyReview() async {
    try {
      await widget.repository.requestWeeklyReview();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing your weekly review. Check back soon.'),
        ),
      );
    } on ProgressSessionException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session expired. Sign out, then sign in again.'),
        ),
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the weekly review. Try again.'),
        ),
      );
    }
  }

  Future<void> _openWeeklyReview(WeeklyProgressReview review) async {
    final acknowledge = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => WeeklyReviewSheet(review: review, now: widget.now()),
    );
    if (acknowledge != true || review.acknowledged) return;
    await widget.repository.acknowledgeWeeklyReview(review.id);
    if (mounted) setState(_reload);
  }

  Future<void> _record() async {
    final result = await showModalBottomSheet<BodyMeasurement>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const MeasurementEntrySheet(),
    );
    if (result == null || !mounted) return;
    try {
      await widget.repository.saveMeasurement(result);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Weigh-in saved')));
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save measurement. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _ensureConsent() async {
    if (_hasConsent) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save private progress photos?'),
        content: const Text(
          'Your photos are stored privately and only you can open them. '
          'They are never sent to an AI model.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I agree and continue'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.repository.grantPhotoStorageConsent();
      _hasConsent = true;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save consent. Try again.')),
        );
      }
    }
  }

  Future<void> _openPhotoCapture() async {
    await _ensureConsent();
    if (!_hasConsent || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
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
    try {
      _activeSet ??= await widget.repository.beginPhotoSet();
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
        requestFullMetadata: false,
      );
      if (photo == null) return (captured: false, error: null);
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
    } catch (e) {
      debugPrint('Non-critical error: $e');
      _activeSet = null;
      _capturedPoses.clear();
      return (
        captured: false,
        error: 'Photo was not saved. Try again when ready.',
      );
    }
  }

  Future<void> _openPhotoSets(List<ProgressPhotoSet> sets) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
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
    try {
      final urls = await widget.repository.createPhotoReadUrls(set);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => PrivatePhotoViewer(urls: urls),
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open private photos. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteSet(ProgressPhotoSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo set?'),
        content: const Text(
          'The photos will be permanently removed. This cannot be undone.',
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
            child: const Text('Delete set'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deletePhotoSet(set);
    if (mounted) setState(_reload);
  }
}

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
