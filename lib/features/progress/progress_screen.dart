import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({required this.repository, this.training, super.key});
  final ProgressRepository repository;
  final TrainingHubRepository? training;
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
  @override
  void initState() {
    super.initState();
    _reload();
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
    TracendCard(
      radius: TracendRadii.decision,
      raised: true,
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TracendPill(
            label: summary.hasTrend ? 'Trend available' : 'Gathering baseline',
            icon: summary.hasTrend
                ? CupertinoIcons.chart_bar_fill
                : CupertinoIcons.plus_circle_fill,
            color: summary.hasTrend
                ? context.tracendColors.stateStable
                : context.tracendColors.actionPrimary,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            summary.hasTrend
                ? 'Your measurements are ready to compare'
                : 'Record two measurements to reveal a trend',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            summary.hasTrend
                ? 'Calculated from confirmed entries. No AI estimation is used.'
                : 'Use the same morning protocol when practical. Manual and HealthKit values keep their source.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Current weight',
                  value: _value(summary.currentWeightKg, 'kg'),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Recorded change',
                  value: _signed(summary.weightChangeKg, 'kg'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    const SectionLabel('Measurements'),
    if (measurements.isEmpty)
      const _EmptyMeasurements()
    else
      _TrendCard(measurements: measurements),
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
          .take(3)
          .map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
              child: _MeasurementRow(value: m),
            ),
          ),
    ],
    const SectionLabel('Training evidence'),
    if (training == null)
      const TracendCard(
        child: Text(
          'Training evidence is unavailable. Measurement and photo review remain available.',
        ),
      )
    else ...[
      TracendCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${training.completedSessions} of ${training.plannedSessions} planned sessions completed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TracendSpacing.sm),
            LinearProgressIndicator(
              value: training.plannedSessions == 0
                  ? 0
                  : (training.completedSessions / training.plannedSessions)
                        .clamp(0, 1)
                        .toDouble(),
            ),
          ],
        ),
      ),
      const SizedBox(height: TracendSpacing.sm),
      if (training.progression.isEmpty)
        const TracendCard(
          child: Text(
            'Strength progression appears after completed comparable sets. Planned loads are never charted.',
          ),
        )
      else
        TracendCard(
          child: Column(
            children: [
              for (final item in training.progression.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.exercise),
                  subtitle: Text('${item.sessions} comparable sessions'),
                  trailing: Text(
                    item.bestLoadKg == null
                        ? '${item.bestRepetitions ?? '—'} reps'
                        : '${item.bestLoadKg} kg',
                  ),
                ),
            ],
          ),
        ),
    ],
    const SectionLabel('Private progress photos'),
    _ActionCard(
      icon: CupertinoIcons.camera_viewfinder,
      title: 'Create a standardized photo set',
      detail: 'Front, side and back · private by default · separate consent',
      action: 'Open capture guide',
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PhotoGuideSheet(onCapture: _captureSet),
      ),
    ),
    if (photoSets.isNotEmpty)
      ...photoSets.map(
        (set) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _PhotoSetCard(
            set: set,
            onView: () => _viewSet(set),
            onDelete: () => _deleteSet(set),
          ),
        ),
      ),
    const SectionLabel('Weekly review'),
    _ActionCard(
      icon: CupertinoIcons.calendar,
      title: weeklyReview != null
          ? 'Weekly review ready'
          : weeklyReviewJob?.isPending == true
          ? 'Weekly review is preparing'
          : weeklyReviewJob?.status == 'failed'
          ? 'Weekly review needs another try'
          : 'Create your weekly review',
      detail: weeklyReview != null
          ? '${_weekLabel(weeklyReview.week)} · deterministic evidence · no AI estimation'
          : weeklyReviewJob?.isPending == true
          ? 'Your evidence is queued privately. The approved plan remains available while it processes.'
          : 'Summarize training, recovery, nutrition and progress without changing your plan.',
      action: weeklyReview != null
          ? 'Open weekly review'
          : weeklyReviewJob?.isPending == true
          ? 'Refresh status'
          : 'Generate review',
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
    } catch (_) {
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
      builder: (_) => _WeeklyReviewSheet(review: review),
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
      builder: (_) => const _MeasurementSheet(),
    );
    if (result == null || !mounted) return;
    try {
      await widget.repository.saveMeasurement(result);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Measurement recorded')));
    } catch (_) {
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

  Future<void> _captureSet() async {
    Navigator.pop(context);
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
      final setId = await widget.repository.beginPhotoSet();
      final picker = ImagePicker();
      for (final pose in const ['front', 'side', 'back']) {
        final shouldOpenCamera = await _confirmPoseCapture(pose);
        if (!shouldOpenCamera) throw StateError('Capture cancelled');
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 1800,
          requestFullMetadata: false,
        );
        if (photo == null) throw StateError('Capture cancelled');
        await widget.repository.uploadPhoto(
          setId: setId,
          pose: pose,
          bytes: await photo.readAsBytes(),
          contentType: 'image/jpeg',
        );
      }
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Private photo set saved')));
    } catch (_) {
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo set was not completed. Retry when ready.'),
          ),
        );
      }
    }
  }

  Future<bool> _confirmPoseCapture(String pose) async {
    final details = switch (pose) {
      'front' => (
        step: '1 of 3',
        title: 'Front photo',
        guidance:
            'Face the camera with your full body visible. Stand naturally with your arms relaxed.',
      ),
      'side' => (
        step: '2 of 3',
        title: 'Side photo',
        guidance:
            'Turn 90 degrees with your full body visible. Keep a natural, relaxed posture.',
      ),
      _ => (
        step: '3 of 3',
        title: 'Back photo',
        guidance:
            'Face away from the camera with your full body visible. Keep your arms relaxed.',
      ),
    };
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(CupertinoIcons.camera_viewfinder),
            title: Text(details.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details.step,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.tracendColors.actionPrimary,
                  ),
                ),
                const SizedBox(height: TracendSpacing.xs),
                Text(details.guidance),
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  'Use similar lighting, distance and clothing each time.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel set'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(CupertinoIcons.camera),
                label: const Text('Open camera'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _viewSet(ProgressPhotoSet set) async {
    try {
      final urls = await widget.repository.createPhotoReadUrls(set);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PrivatePhotoViewer(urls: urls),
      );
    } catch (_) {
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

  String _value(double? v, String unit) =>
      v == null ? 'Not recorded' : '${v.toStringAsFixed(1)} $unit';
  String _signed(double? v, String unit) => v == null
      ? 'Not enough data'
      : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} $unit';

  String _weekLabel(DateTime week) =>
      'Week of ${week.day}/${week.month}/${week.year}';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

class _EmptyMeasurements extends StatelessWidget {
  const _EmptyMeasurements();
  @override
  Widget build(BuildContext context) => const TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.chart_bar),
        SizedBox(height: 12),
        Text('No measurements yet'),
        SizedBox(height: 4),
        Text(
          'Your first confirmed entry becomes the baseline. A trend needs at least two dates.',
        ),
      ],
    ),
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.measurements});
  final List<BodyMeasurement> measurements;
  @override
  Widget build(BuildContext context) {
    final first = measurements.first.weightKg,
        last = measurements.last.weightKg;
    return TracendCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weight history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${measurements.length} confirmed ${measurements.length == 1 ? 'entry' : 'entries'} · kilograms',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Semantics(
            label:
                'Weight history from ${first.toStringAsFixed(1)} to ${last.toStringAsFixed(1)} kilograms across ${measurements.length} entries.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 132,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    values: measurements.map((m) => m.weightKg).toList(),
                    line: context.tracendColors.actionPrimary,
                    grid: context.tracendColors.borderSubtle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${first.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(
                '${last.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.line,
    required this.grid,
  });
  final List<double> values;
  final Color line, grid;
  @override
  void paint(Canvas c, Size s) {
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = s.height * i / 4;
      c.drawLine(Offset(0, y), Offset(s.width, y), gp);
    }
    if (values.isEmpty) return;
    final minV = values.reduce(math.min),
        maxV = values.reduce(math.max),
        range = math.max(maxV - minV, 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? s.width / 2
          : s.width * i / (values.length - 1);
      final y = s.height - 12 - ((values[i] - minV) / range) * (s.height - 24);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      c.drawCircle(Offset(x, y), 4, Paint()..color = line);
    }
    c.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.line != line || old.grid != grid;
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({required this.value});
  final BodyMeasurement value;
  @override
  Widget build(BuildContext context) => TracendCard(
    child: Row(
      children: [
        const Icon(CupertinoIcons.checkmark_seal_fill),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${value.weightKg.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${value.date.day}/${value.date.month}/${value.date.year} · ${value.source}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (value.waistCm != null)
          Text('${value.waistCm!.toStringAsFixed(1)} cm waist'),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String title, detail, action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.tracendColors.actionPrimary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(detail, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}

class _MeasurementSheet extends StatefulWidget {
  const _MeasurementSheet();
  @override
  State<_MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends State<_MeasurementSheet> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(6, (_) => TextEditingController());
  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  double? n(int i) => fields[i].text.trim().isEmpty
      ? null
      : double.tryParse(fields[i].text.trim());
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Form(
      key: form,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record measurement',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Confirmed manual entry · kilograms and centimeters',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...[
              'Weight *',
              'Waist',
              'Chest',
              'Hip',
              'Arm',
              'Thigh',
            ].asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: fields[e.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: e.key == 5
                      ? TextInputAction.done
                      : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: e.value,
                    suffixText: e.key == 0 ? 'kg' : 'cm',
                  ),
                  validator: (v) {
                    if (e.key == 0 && n(0) == null) {
                      return 'Enter a valid weight';
                    }
                    if (v!.isNotEmpty && n(e.key) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    BodyMeasurement(
                      date: DateTime.now(),
                      weightKg: n(0)!,
                      waistCm: n(1),
                      chestCm: n(2),
                      hipCm: n(3),
                      armCm: n(4),
                      thighCm: n(5),
                    ),
                  );
                },
                child: const Text('Save measurement'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PhotoSetCard extends StatelessWidget {
  const _PhotoSetCard({
    required this.set,
    required this.onView,
    required this.onDelete,
  });
  final ProgressPhotoSet set;
  final VoidCallback onView, onDelete;
  @override
  Widget build(BuildContext context) => TracendCard(
    child: Row(
      children: [
        const Icon(CupertinoIcons.lock_shield_fill),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${set.date.day}/${set.date.month}/${set.date.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${set.objectKeys.length} private photos · ${set.status}'),
            ],
          ),
        ),
        TextButton(onPressed: onView, child: const Text('View')),
        IconButton(
          onPressed: onDelete,
          tooltip: 'Delete photo set',
          icon: const Icon(CupertinoIcons.delete),
        ),
      ],
    ),
  );
}

class _PrivatePhotoViewer extends StatelessWidget {
  const _PrivatePhotoViewer({required this.urls});
  final List<String> urls;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private photo set',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text('Short-lived access · links expire after 60 seconds'),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('Photo unavailable')),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PhotoGuideSheet extends StatelessWidget {
  const _PhotoGuideSheet({required this.onCapture});
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standardized photo set',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Photos are restricted data. Storage consent and AI-analysis consent are separate. This foundation does not send photos to an AI provider.',
            ),
            const SizedBox(height: 20),
            for (final item in const [
              (
                '1',
                'Same timing',
                'Use a repeatable time of day, ideally before training.',
              ),
              (
                '2',
                'Same environment',
                'Match distance, camera height, lighting and clothing.',
              ),
              (
                '3',
                'Three poses',
                'Capture front, side and back. Retake any unclear frame.',
              ),
              (
                '4',
                'Private review',
                'Photos stay out of Today, notifications, analytics and general logs.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TracendPill(label: item.$1, compact: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(item.$3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCapture,
                child: const Text('Capture front, side and back'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeeklyReviewSheet extends StatelessWidget {
  const _WeeklyReviewSheet({required this.review});
  final WeeklyProgressReview review;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly review',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A deterministic editorial review of confirmed evidence. Missing inputs remain visible.',
            ),
            const SizedBox(height: 20),
            _ReviewSection('1 · Outcome', _outcome(review.outcomeCode)),
            _ReviewSection(
              '2 · Execution and adherence',
              '${review.completedWorkouts} of ${review.plannedSessions} planned workouts completed (${review.adherencePercent}%). ${review.completedSets} working sets were confirmed.',
            ),
            _ReviewSection(
              '3 · Recovery context',
              '${review.checkInDays} check-in days · ${review.healthDays} Apple Health days. Average energy ${_metric(review.averageEnergy)} and soreness ${_metric(review.averageSoreness)}.',
            ),
            _ReviewSection(
              '4 · Training and nutrition evidence',
              '${review.confirmedNutritionDays} days include confirmed nutrition. ${review.measurementDays} measurement days were recorded.',
            ),
            const _ReviewSection(
              '5 · What remains unchanged',
              'Your approved training plan and nutrition targets remain active. No persistent plan change is implied by this review.',
            ),
            _ReviewSection(
              '6 · Missing evidence',
              review.missingData.isEmpty
                  ? 'No required evidence category is completely missing.'
                  : review.missingData.map(_missingLabel).join(' · '),
            ),
            _ReviewSection(
              '7 · Next-week focus',
              _nextFocus(review.nextFocusCode),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, !review.acknowledged),
                child: Text(review.acknowledged ? 'Done' : 'Mark reviewed'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _metric(double? value) =>
      value == null ? 'not recorded' : '${value.toStringAsFixed(1)} of 5';

  static String _outcome(String code) => switch (code) {
    'week_observed' =>
      'The week has enough execution and recovery evidence to review.',
    'training_logged_recovery_missing' =>
      'Training was logged, but recovery evidence is incomplete.',
    _ => 'More execution evidence is needed before drawing a weekly pattern.',
  };

  static String _nextFocus(String code) => switch (code) {
    'complete_next_planned_workout' => 'Complete the next planned workout.',
    'record_recovery_check_in' => 'Record recovery after your next session.',
    'confirm_nutrition' => 'Confirm nutrition on the days you track meals.',
    _ => 'Continue the approved plan and keep the evidence comparable.',
  };

  static String _missingLabel(String code) => switch (code) {
    'active_training_plan' => 'Active training plan',
    'recovery_check_ins' => 'Recovery check-ins',
    'confirmed_nutrition' => 'Confirmed nutrition',
    'health_context' => 'Apple Health context',
    _ => 'Additional evidence',
  };
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(body),
      ],
    ),
  );
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
