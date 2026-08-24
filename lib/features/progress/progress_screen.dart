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
import 'package:tracend/features/progress/weight_trend_indicator.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    required this.repository,
    this.training,
    this.brief,
    super.key,
  });
  final ProgressRepository repository;
  final TrainingHubRepository? training;
  final DailyBriefRepository? brief;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<
    ({
      List<BodyMeasurement> measurements,
      ProgressSummary summary,
      List<ProgressPhotoSet> photoSets,
      WeeklyProgressReview? weeklyReview,
      WeeklyReviewJob? weeklyReviewJob,
      TrainingHubData? training,
    })
  >
  _future;
  int _periodDays = 84;
  String? _activeSet;
  final Set<String> _capturedPoses = {};
  bool _hasConsent = false;
  late final Future<DailyBrief> _brief;
  @override
  void initState() {
    super.initState();
    _reload();
    _brief = (widget.brief ?? const FixtureDailyBriefRepository()).load(
      DateTime.now(),
    );
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
      return TracendScrollView(
        title: 'Progress',
        subtitle: 'Measured evidence, reviewed over time',
        children: [
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            _ErrorCard(
              onRetry: () {
                setState(_reload);
              },
            )
          else
            ..._content(
              context,
              data!.measurements,
              data.summary,
              data.photoSets,
              data.weeklyReview,
              data.weeklyReviewJob,
              data.training,
            ),
        ],
      );
    },
  );

  List<Widget> _content(
    BuildContext context,
    List<BodyMeasurement> measurements,
    ProgressSummary summary,
    List<ProgressPhotoSet> photoSets,
    WeeklyProgressReview? weeklyReview,
    WeeklyReviewJob? weeklyReviewJob,
    TrainingHubData? training,
  ) => [
    ProgressSnapshotCard(measurements: measurements, fallback: summary),
    const SectionLabel('Weight history'),
    if (measurements.isEmpty)
      const EmptyMeasurementsCard()
    else
      FutureBuilder<DailyBrief>(
        future: _brief,
        builder: (context, snapshot) => WeightTrendCard(
          measurements: measurements,
          computed: snapshot.data?.computed,
        ),
      ),
    FutureBuilder<DailyBrief>(
      future: _brief,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.computed != null) {
          return WeightTrendIndicator(
            computed: snapshot.data!.computed!,
            sparklineValues: measurements.isEmpty
                ? null
                : measurements.map((m) => m.weightKg).toList(),
          );
        }
        return const SizedBox.shrink();
      },
    ),
    const SizedBox(height: TracendSpacing.sm),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('record-measurement'),
        onPressed: _record,
        icon: const Icon(CupertinoIcons.plus),
        label: const Text('Record measurement'),
      ),
    ),
    if (measurements.isNotEmpty) ...[
      const SizedBox(height: TracendSpacing.sm),
      ...measurements.reversed
          .take(8)
          .map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
              child: MeasurementHistoryRow(
                value: m,
                onOpen: () => _openMeasurementDetail(m),
              ),
            ),
          ),
    ],
    const SectionLabel('Training evidence'),
    TrainingEvidenceSection(training: training),
    const SectionLabel('Private progress photos'),
    PosePhotoRow(
      pose: 'front',
      label: 'Front photo',
      guidance: 'Face the camera with full body visible',
      isCaptured: _activeSet != null && _capturedPoses.contains('front'),
      onCamera: () => _capturePose('front', ImageSource.camera),
      onGallery: () => _capturePose('front', ImageSource.gallery),
    ),
    PosePhotoRow(
      pose: 'side',
      label: 'Side photo',
      guidance: 'Turn 90 degrees, arm away from body',
      isCaptured: _activeSet != null && _capturedPoses.contains('side'),
      onCamera: () => _capturePose('side', ImageSource.camera),
      onGallery: () => _capturePose('side', ImageSource.gallery),
    ),
    PosePhotoRow(
      pose: 'back',
      label: 'Back photo',
      guidance: 'Face away from camera, natural stance',
      isCaptured: _activeSet != null && _capturedPoses.contains('back'),
      onCamera: () => _capturePose('back', ImageSource.camera),
      onGallery: () => _capturePose('back', ImageSource.gallery),
    ),
    PosePhotoRow(
      pose: 'lower',
      label: 'Lower body',
      guidance: 'Full lower body from waist down',
      isCaptured: _activeSet != null && _capturedPoses.contains('lower'),
      onCamera: () => _capturePose('lower', ImageSource.camera),
      onGallery: () => _capturePose('lower', ImageSource.gallery),
    ),
    if (photoSets.isNotEmpty)
      ...photoSets.map(
        (set) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PhotoSetCard(
            set: set,
            onView: () => _viewSet(set),
            onDelete: () => _deleteSet(set),
          ),
        ),
      ),
    const SectionLabel('Weekly review'),
    WeeklyReviewActionCard(
      weeklyReview: weeklyReview,
      weeklyReviewJob: weeklyReviewJob,
      onTap: weeklyReview != null
          ? () => _openWeeklyReview(weeklyReview)
          : weeklyReviewJob?.isPending == true
          ? () => setState(_reload)
          : _requestWeeklyReview,
    ),
    const SectionLabel('Training review period'),
    Material(
      color: Colors.transparent,
      child: Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          for (final option in const [
            (label: '4 weeks', days: 28),
            (label: '12 weeks', days: 84),
            (label: '6 months', days: 182),
          ])
            ChoiceChip(
              label: Text(option.label),
              selected: _periodDays == option.days,
              onSelected: (_) => setState(() {
                _periodDays = option.days;
                _reload();
              }),
            ),
        ],
      ),
    ),
  ];

  Future<void> _openMeasurementDetail(BodyMeasurement measurement) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MeasurementDetailSheet(measurement: measurement),
    );
  }

  Future<void> _requestWeeklyReview() async {
    try {
      await widget.repository.requestWeeklyReview();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weekly review queued. Refresh in a few minutes.'),
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
          content: Text('Could not queue the weekly review. Try again.'),
        ),
      );
    }
  }

  Future<void> _openWeeklyReview(WeeklyProgressReview review) async {
    final acknowledge = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WeeklyReviewSheet(review: review),
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
      ).showSnackBar(const SnackBar(content: Text('Measurement recorded')));
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
          'Front, side and back photos will be stored privately. They will not be sent to Gemini or analyzed by AI.',
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

  Future<void> _capturePose(String pose, ImageSource source) async {
    await _ensureConsent();
    if (!_hasConsent || !mounted) return;

    try {
      _activeSet ??= await widget.repository.beginPhotoSet();
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      await widget.repository.uploadPhoto(
        setId: _activeSet!,
        pose: pose,
        bytes: await photo.readAsBytes(),
        contentType: 'image/jpeg',
      );
      _capturedPoses.add(pose);
      if (_capturedPoses.length == 4) {
        _activeSet = null;
        _capturedPoses.clear();
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      _activeSet = null;
      _capturedPoses.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo was not saved. Retry when ready.'),
          ),
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(_reload);
    }
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
          'The private images and progress records will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
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
  Widget build(BuildContext context) => TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Progress could not be loaded.'),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
