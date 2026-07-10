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
import 'package:tracend/shared/widgets/trajectory_lens.dart';

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
                      const TracendPill(
                        label: 'Do this next',
                        icon: CupertinoIcons.location_fill,
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      TrajectoryLens(
                        decision: brief.nextAction,
                        evidence: [
                          if (brief.checkIn != null) 'Check-in',
                          if (brief.health != null) 'Apple Health',
                          if (brief.workout != null) 'Approved plan',
                          if (brief.nextMeal != null) 'Meal schedule',
                        ],
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      Text(
                        brief.nextAction,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: TracendSpacing.xs),
                      Text(
                        brief.reason,
                        style: Theme.of(context).textTheme.bodyLarge,
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
        const SectionLabel('Health context'),
        HealthStatusCard(
          repository: widget.health,
          onSynced: () => setState(_reloadBriefAndHealth),
        ),
        const SectionLabel('Apple Health evidence'),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 3 : 2;
                  final cellWidth =
                      (constraints.maxWidth -
                          (TracendSpacing.sm * (columns - 1))) /
                      columns;
                  return Wrap(
                    spacing: TracendSpacing.sm,
                    runSpacing: TracendSpacing.sm,
                    children: [
                      _SignalMetric(
                        width: cellWidth,
                        label: 'Sleep',
                        value: latest.sleepMinutes == null
                            ? 'No data'
                            : _duration(latest.sleepMinutes!),
                      ),
                      _SignalMetric(
                        width: cellWidth,
                        label: 'Steps',
                        value: latest.steps?.toString() ?? 'No data',
                      ),
                      _SignalMetric(
                        width: cellWidth,
                        label: 'Active energy',
                        value: latest.activeEnergyKcal == null
                            ? 'No data'
                            : '${latest.activeEnergyKcal!.round()} kcal',
                      ),
                      _SignalMetric(
                        width: cellWidth,
                        label: 'Resting HR',
                        value: latest.restingHeartRateBpm == null
                            ? 'No data'
                            : '${latest.restingHeartRateBpm!.round()} bpm',
                      ),
                      _SignalMetric(
                        width: cellWidth,
                        label: 'HRV (SDNN)',
                        value: latest.hrvSdnnMs == null
                            ? 'No data'
                            : '${latest.hrvSdnnMs!.round()} ms',
                      ),
                      _SignalMetric(
                        width: cellWidth,
                        label: 'Workouts',
                        value: latest.workoutCount?.toString() ?? 'No data',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (sleep.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Sleep duration',
            values: sleep.map((day) => day.sleepMinutes! / 60).toList(),
            start: sleep.first.date,
            end: sleep.last.date,
            unit: 'hours',
          ),
        ],
        if (steps.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Daily steps',
            values: steps.map((day) => day.steps!.toDouble()).toList(),
            start: steps.first.date,
            end: steps.last.date,
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
  const _SignalMetric({
    required this.label,
    required this.value,
    required this.width,
  });
  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DecoratedBox(
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
    ),
  );
}

class _HealthTrend extends StatelessWidget {
  const _HealthTrend({
    required this.title,
    required this.values,
    required this.start,
    required this.end,
    required this.unit,
  });
  final String title;
  final List<double> values;
  final DateTime start;
  final DateTime end;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final latest = values.last;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '${_format(latest)} $unit · ${values.length} recorded days',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.sm),
          MiniTrendChart(
            values: values,
            label:
                '$title from ${_date(start)} to ${_date(end)}. Latest ${_format(latest)} $unit.',
            height: 88,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(_date(start)), Text(_date(end))],
          ),
        ],
      ),
    );
  }

  String _format(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  String _date(DateTime date) => '${date.day}/${date.month}';
}
