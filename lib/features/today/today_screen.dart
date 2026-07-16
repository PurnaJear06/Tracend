import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/today/check_in_sheet.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/evidence_trend_chart.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.environment,
    this.onSignOut,
    this.workouts,
    this.health = const ManualHealthRepository(),
    this.coach = const FixtureCoachRepository(),
    this.brief = const FixtureDailyBriefRepository(),
    super.key,
  });

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;
  final WorkoutRepository? workouts;
  final HealthRepository health;
  final CoachRepository coach;
  final DailyBriefRepository brief;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<HealthHistory> _healthHistory;
  late Future<DailyBrief> _brief;

  @override
  void initState() {
    super.initState();
    _reloadHealth();
    _brief = widget.brief.load(DateTime.now());
  }

  void _reloadHealth() {
    _healthHistory = widget.health.loadHistory();
  }

  void _reloadBriefAndHealth() {
    _reloadHealth();
    _brief = widget.brief.load(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return TracendScrollView(
      title: 'Today',
      subtitle: _formattedDate(now),
      trailing: IconButton(
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        tooltip: 'Open account',
        icon: const Icon(CupertinoIcons.person_crop_circle),
        onPressed: () => Navigator.of(context).push<void>(
          CupertinoPageRoute(
            builder: (_) => AccountScreen(
              environment: widget.environment,
              onSignOut: widget.onSignOut,
              health: widget.health,
              coach: widget.coach,
              notifications: widget.environment.hasSupabaseConfiguration
                  ? SupabaseNotificationRepository(Supabase.instance.client)
                  : const FixtureNotificationRepository(),
              exports: widget.environment.hasSupabaseConfiguration
                  ? SupabasePrivacyExportRepository(Supabase.instance.client)
                  : const FixturePrivacyExportRepository(),
              deletion: widget.environment.hasSupabaseConfiguration
                  ? SupabaseAccountDeletionRepository(Supabase.instance.client)
                  : const FixtureAccountDeletionRepository(),
            ),
          ),
        ),
      ),
      children: [
        FutureBuilder<DailyBrief>(
          future: _brief,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const TracendCard(
                radius: TracendRadii.decision,
                child: LinearProgressIndicator(),
              );
            }
            final brief = snapshot.data;
            if (brief == null) {
              return TracendCard(
                radius: TracendRadii.decision,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use your approved plan.',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: TracendSpacing.xs),
                    const Text(
                      'The daily brief is unavailable. Workout and meal logging remain available.',
                    ),
                  ],
                ),
              );
            }
            final hasWorkout = brief.workout != null;
            return Column(
              children: [
                TracendCard(
                  radius: TracendRadii.decision,
                  padding: const EdgeInsets.all(TracendSpacing.gutter),
                  raised: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TodayHeroBackdrop(
                        action: brief.nextAction,
                        reason: brief.reason,
                      ),
                      const SizedBox(height: TracendSpacing.md),
                      _ReadinessStrip(
                        brief: brief,
                        onOpen: (title, detail) =>
                            _showReadinessDetail(context, title, detail),
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: Icon(
                            brief.checkIn == null
                                ? CupertinoIcons.slider_horizontal_3
                                : CupertinoIcons.play_fill,
                            size: 18,
                          ),
                          label: Text(
                            brief.checkIn == null
                                ? 'Add check-in'
                                : hasWorkout
                                ? 'Open workout'
                                : 'No workout today',
                          ),
                          onPressed: brief.checkIn == null
                              ? () async {
                                  await showCheckInSheet(
                                    context,
                                    widget.environment,
                                  );
                                  if (mounted) {
                                    setState(
                                      () => _brief = widget.brief.load(
                                        DateTime.now(),
                                      ),
                                    );
                                  }
                                }
                              : hasWorkout
                              ? () => Navigator.of(context).push<void>(
                                  CupertinoPageRoute(
                                    builder: (_) => WorkoutDetailScreen(
                                      repository: widget.workouts,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: TracendSpacing.xs),
                      Material(
                        color: Colors.transparent,
                        child: ExpansionTile(
                          key: const PageStorageKey('today-evidence'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text('See evidence'),
                          children: [
                            _BriefEvidence(
                              label: 'Check-in',
                              available: brief.checkIn != null,
                              detail: brief.checkIn == null
                                  ? 'Add today’s recovery input'
                                  : 'Current user-confirmed input',
                            ),
                            _BriefEvidence(
                              label: 'Apple Health',
                              available: brief.health != null,
                              detail: brief.health == null
                                  ? 'No fresh summary for today'
                                  : 'Dated normalized summary',
                            ),
                            _BriefEvidence(
                              label: 'Training plan',
                              available: brief.workout != null,
                              detail:
                                  brief.workout?['name'] as String? ??
                                  'No workout assigned today',
                            ),
                            _BriefEvidence(
                              label: 'Meal schedule',
                              available: brief.nextMeal != null,
                              detail:
                                  brief.nextMeal?['label'] as String? ??
                                  'No remaining meal',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Today’s timeline'),
                TracendCard(
                  child: Column(
                    children: [
                      _TimelineRow(
                        icon: CupertinoIcons.slider_horizontal_3,
                        title: 'Check-in',
                        detail: brief.checkIn == null
                            ? 'Needed · about 1 min'
                            : 'Completed',
                      ),
                      const Divider(height: TracendSpacing.lg),
                      _TimelineRow(
                        icon: CupertinoIcons.bolt_fill,
                        title:
                            brief.workout?['name'] as String? ?? 'Recovery day',
                        detail: brief.workout == null
                            ? 'No planned workout'
                            : 'Approved training plan',
                      ),
                      if (brief.nextMeal != null) ...[
                        const Divider(height: TracendSpacing.lg),
                        _TimelineRow(
                          icon: CupertinoIcons.clock_fill,
                          title: brief.nextMeal!['label'] as String,
                          detail:
                              '${brief.nextMeal!['local_time']} · ${brief.nextMeal!['status']}',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SectionLabel('Apple Health'),
        HealthStatusCard(
          repository: widget.health,
          onSynced: () => setState(_reloadBriefAndHealth),
        ),
        const SizedBox(height: TracendSpacing.sm),
        FutureBuilder<HealthHistory>(
          future: _healthHistory,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const TracendCard(child: LinearProgressIndicator());
            }
            if (snapshot.hasError) {
              return TracendCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health history could not load',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: TracendSpacing.xs),
                    const Text('Refresh the summary or try again.'),
                  ],
                ),
              );
            }
            return _HealthEvidence(history: snapshot.data!);
          },
        ),
        const SectionLabel('Daily check-in'),
        TracendCard(
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add today’s check-in'),
              subtitle: const Text(
                'Sleep, energy, soreness, hunger, mood and pain · 1 min',
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: () async {
                await showCheckInSheet(context, widget.environment);
                if (context.mounted) {
                  setState(() => _brief = widget.brief.load(DateTime.now()));
                }
              },
            ),
          ),
        ),
        const SectionLabel('Latest coaching decision'),
        FutureBuilder<CoachDecision?>(
          future: widget.coach.loadLatest(),
          builder: (context, snapshot) {
            final decision = snapshot.data;
            if (decision == null) {
              return const TracendCard(
                child: Text(
                  'Open Coach to generate an evidence-backed daily decision.',
                ),
              );
            }
            return TracendCard(
              raised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    decision.finalDecision,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  Text(decision.reason),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _formattedDate(DateTime value) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[value.weekday - 1]}, ${value.day} '
        '${months[value.month - 1]}';
  }

  Future<void> _showReadinessDetail(
    BuildContext context,
    String title,
    String detail,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.sm,
        TracendSpacing.gutter,
        TracendSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: TracendSpacing.xs),
          Text(detail, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    ),
  );
}

class _TodayHeroBackdrop extends StatelessWidget {
  const _TodayHeroBackdrop({required this.action, required this.reason});
  final String action, reason;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(TracendRadii.card),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/visuals/tracend-coaching-horizon-v1.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .18),
              Colors.black.withValues(alpha: .84),
            ],
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 250),
          child: Padding(
            padding: const EdgeInsets.all(TracendSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TracendPill(
                  label: 'Your next move',
                  icon: CupertinoIcons.location_fill,
                  compact: true,
                ),
                const SizedBox(height: 92),
                Text(
                  action,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: TracendSpacing.xs),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .86),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReadinessStrip extends StatelessWidget {
  const _ReadinessStrip({required this.brief, required this.onOpen});
  final DailyBrief brief;
  final void Function(String title, String detail) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Recovery',
        brief.checkIn == null ? 'Check in' : 'Updated',
        CupertinoIcons.heart_fill,
        brief.checkIn == null
            ? 'Tracend needs today’s energy, sleep, soreness and pain check-in before adapting your session.'
            : 'Today’s user-confirmed recovery check-in is available to the coach.',
      ),
      (
        'Training',
        brief.workout == null ? 'Rest day' : 'Planned',
        CupertinoIcons.bolt_fill,
        brief.workout == null
            ? 'Your approved plan has no workout assigned today.'
            : '${brief.workout!['name']} comes from your active approved plan.',
      ),
      (
        'Nutrition',
        brief.nextMeal == null ? 'Up to date' : 'Next meal',
        CupertinoIcons.leaf_arrow_circlepath,
        brief.nextMeal == null
            ? 'There is no remaining scheduled meal action right now.'
            : '${brief.nextMeal!['label']} is next at ${brief.nextMeal!['local_time']}.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s readiness',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: _ReadinessTile(
                  label: items[i].$1,
                  value: items[i].$2,
                  icon: items[i].$3,
                  onTap: () => onOpen(items[i].$1, items[i].$4),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tracendColors.surface,
    borderRadius: BorderRadius.circular(TracendRadii.control),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(TracendSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: context.tracendColors.actionPrimary),
            const SizedBox(height: TracendSpacing.sm),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.tracendColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BriefEvidence extends StatelessWidget {
  const _BriefEvidence({
    required this.label,
    required this.available,
    required this.detail,
  });
  final String label;
  final bool available;
  final String detail;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      available
          ? CupertinoIcons.check_mark_circled_solid
          : CupertinoIcons.exclamationmark_circle,
      color: available
          ? context.tracendColors.stateStable
          : context.tracendColors.stateAttention,
    ),
    title: Text(label),
    subtitle: Text(detail),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: context.tracendColors.actionPrimary),
      const SizedBox(width: TracendSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

class _HealthEvidence extends StatelessWidget {
  const _HealthEvidence({required this.history});

  final HealthHistory history;

  @override
  Widget build(BuildContext context) {
    final latest = history.latest;
    if (latest == null) {
      return const TracendCard(
        child: Text(
          'No Apple Health summaries are stored yet. Refresh after granting access, or continue with the daily check-in.',
        ),
      );
    }
    final sleep = history.days
        .where((day) => day.sleepMinutes != null)
        .toList();
    final steps = history.days.where((day) => day.steps != null).toList();
    return Column(
      children: [
        TracendCard(
          raised: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Latest stored day · ${_shortDate(latest.date)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: TracendSpacing.md),
              Text(
                'What matters today',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: TracendSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _SignalMetric(
                      label: 'Steps',
                      value: latest.steps?.toString() ?? '—',
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: _SignalMetric(
                      label: 'Sleep',
                      value: latest.sleepMinutes == null
                          ? '—'
                          : _duration(latest.sleepMinutes!),
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: _SignalMetric(
                      label: 'Training',
                      value: latest.workoutMinutes == null
                          ? '—'
                          : '${latest.workoutMinutes}m',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.sm),
              Text(
                latest.sleepMinutes == null
                    ? 'Activity is available. Recovery guidance relies more on your check-in because sleep was not found.'
                    : 'Activity and sleep are available to your Coach for today’s recovery context.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: const PageStorageKey('today-more-health'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('More health details'),
                  children: [
                    _HealthDetail(
                      label: 'Active energy',
                      value: latest.activeEnergyKcal == null
                          ? 'Not found'
                          : '${latest.activeEnergyKcal!.round()} kcal',
                    ),
                    _HealthDetail(
                      label: 'Resting heart rate',
                      value: latest.restingHeartRateBpm == null
                          ? 'Not found'
                          : '${latest.restingHeartRateBpm!.round()} bpm',
                    ),
                    _HealthDetail(
                      label: 'HRV (SDNN)',
                      value: latest.hrvSdnnMs == null
                          ? 'Not found'
                          : '${latest.hrvSdnnMs!.round()} ms',
                    ),
                    _HealthDetail(
                      label: 'Weight',
                      value: latest.weightKg == null
                          ? 'Not found'
                          : '${latest.weightKg!.toStringAsFixed(1)} kg',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (sleep.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Sleep duration',
            points: sleep
                .map((day) => DatedTrendValue(day.date, day.sleepMinutes! / 60))
                .toList(),
            unit: 'hours',
          ),
        ],
        if (steps.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Daily steps',
            points: steps
                .map((day) => DatedTrendValue(day.date, day.steps!.toDouble()))
                .toList(),
            unit: 'steps',
          ),
        ],
        if (sleep.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.sm),
            child: TracendCard(
              child: Text(
                'Sleep has no stored samples. Confirm Apple Health contains sleep records and that Tracend has Sleep read access; an empty query cannot tell us which one is missing.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }

  static String _duration(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
  static String _shortDate(DateTime date) => '${date.day}/${date.month}';
}

class _SignalMetric extends StatelessWidget {
  const _SignalMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tracendColors.surfaceRaised,
      borderRadius: BorderRadius.circular(TracendRadii.control),
    ),
    child: Padding(
      padding: const EdgeInsets.all(TracendSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _HealthDetail extends StatelessWidget {
  const _HealthDetail({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}

class _HealthTrend extends StatelessWidget {
  const _HealthTrend({
    required this.title,
    required this.points,
    required this.unit,
  });
  final String title;
  final List<DatedTrendValue> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final latest = points.last.value;
    final average =
        points.fold<double>(0, (sum, item) => sum + item.value) / points.length;
    final difference = latest - average;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '${_format(latest)} $unit today · ${difference >= 0 ? '+' : ''}${_format(difference)} vs average',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.sm),
          EvidenceTrendChart(
            values: points,
            unit: unit,
            average: average,
            compact: true,
            semanticLabel:
                '$title from ${_date(points.first.date)} to ${_date(points.last.date)}. Latest ${_format(latest)} $unit. Average ${_format(average)}.',
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Dots are recorded days. Gaps follow the real calendar; the thin line marks your recorded average.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _format(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  String _date(DateTime date) => '${date.day}/${date.month}';
}
