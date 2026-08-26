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
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/today/check_in_sheet.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/sleep_architecture_card.dart';
import 'package:tracend/features/today/widgets/check_in_prompt_bar.dart';
import 'package:tracend/features/today/widgets/coach_perspective_card.dart';
import 'package:tracend/features/today/widgets/metabolic_target_card.dart';
import 'package:tracend/features/today/widgets/precision_divider.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';
import 'package:tracend/features/today/widgets/session_plan_card.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/trajectory_trend.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.environment,
    this.onSignOut,
    this.workouts,
    this.health = const ManualHealthRepository(),
    this.coach = const FixtureCoachRepository(),
    this.brief = const FixtureDailyBriefRepository(),
    this.nutrition = const FixtureNutritionRepository(),
    this.onOpenProgress,
    this.onOpenNutrition,
    super.key,
  });

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;
  final WorkoutRepository? workouts;
  final HealthRepository health;
  final CoachRepository coach;
  final DailyBriefRepository brief;
  final NutritionRepository nutrition;

  /// Shell wiring: switch to the Progress tab ("View analytics").
  final VoidCallback? onOpenProgress;

  /// Shell wiring: switch to the Nutrition tab ("LOG").
  final VoidCallback? onOpenNutrition;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<HealthHistory> _healthHistory;
  late Future<DailyBrief> _brief;
  late Future<NutritionTargets?> _targets;
  late Future<CoachDecision?> _latestDecision;
  bool _syncing = false;

  /// Auto health sync runs at most once per 30 minutes and never triggers a
  /// permission prompt: it fires only when a previous sync already succeeded.
  static const _autoSyncInterval = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _reloadHealth();
    _targets = widget.nutrition.loadTargets();
    _brief = widget.brief.load(DateTime.now());
    _latestDecision = widget.coach.loadLatest();
    _autoSyncHealthIfNeeded();
  }

  void _reloadHealth() {
    _healthHistory = widget.health.loadHistory();
  }

  void _reloadBriefAndHealth() {
    _reloadHealth();
    setState(() {
      _brief = widget.brief.load(DateTime.now());
    });
  }

  Future<void> _autoSyncHealthIfNeeded() async {
    if (!widget.environment.hasSupabaseConfiguration) return;
    try {
      final status = await widget.health.loadStatus();
      final last = status.lastSuccessfulSync;
      if (last == null) return; // never connected -> manual via profile only
      if (DateTime.now().difference(last) < _autoSyncInterval) return;
      await widget.health.sync();
      if (mounted) _reloadBriefAndHealth();
    } catch (_) {
      // Silent: the hero sync button stays available for an explicit retry.
    }
  }

  /// Sync everything: Apple Health (when connected), the daily brief, and
  /// today's coaching decision. Each stage fails independently and the result
  /// message reports exactly what could not be refreshed — a HealthKit read
  /// that returns `unavailable` counts as a failure, and a never-connected
  /// Apple Health is reported as skipped, never as "up to date".
  Future<void> _syncEverything() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final failures = <String>[];
    var healthSkipped = false;
    try {
      try {
        final status = await widget.health.loadStatus();
        if (status.lastSuccessfulSync != null) {
          final synced = await widget.health.sync();
          if (synced.state == HealthConnectionState.unavailable) {
            failures.add('Apple Health');
          }
        } else {
          healthSkipped = true;
        }
      } catch (_) {
        failures.add('Apple Health');
      }
      if (!mounted) return;
      _reloadBriefAndHealth();
      if (widget.environment.hasSupabaseConfiguration) {
        try {
          final latest = await widget.coach.loadLatest();
          final today = _dateKey(DateTime.now());
          if (latest == null || latest.localDate != today) {
            await widget.coach.generate();
          }
          if (!mounted) return;
          setState(() {
            _latestDecision = widget.coach.loadLatest();
          });
        } catch (_) {
          failures.add('coach decision');
        }
      }
      if (!mounted) return;
      final String message;
      if (failures.isNotEmpty) {
        message = 'Synced, but unavailable: ${failures.join(', ')}.';
      } else if (healthSkipped) {
        message =
            'Synced. Apple Health is not connected — set it up in your profile.';
      } else {
        message = 'Everything is up to date.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _openCheckIn() async {
    await showCheckInSheet(context, widget.environment);
    if (mounted) {
      setState(() {
        _brief = widget.brief.load(DateTime.now());
      });
    }
  }

  void _openWorkout() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => WorkoutDetailScreen(repository: widget.workouts),
      ),
    );
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
            // FutureBuilder retains the previous data when the future is
            // swapped (check-in / health sync reloads). Prefer it over the
            // waiting state so _BriefContent stays mounted: stagger
            // entrances don't replay and score count-ups animate on change.
            final brief = snapshot.data;
            if (brief != null) {
              return _BriefContent(
                brief: brief,
                targets: _targets,
                latestDecision: _latestDecision,
                healthHistory: _healthHistory,
                syncing: _syncing,
                onSync: _syncEverything,
                onStartSession: brief.workout != null ? _openWorkout : null,
                onViewAnalytics: widget.onOpenProgress,
                onOpenNutrition: widget.onOpenNutrition,
                onOpenWorkout: _openWorkout,
                onCheckIn: _openCheckIn,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const TracendCard(
                radius: TracendRadii.decision,
                child: LinearProgressIndicator(),
              );
            }
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

/// The loaded-brief composition (Chunk 6 layout): hero → recovery readout →
/// 7-day trend → precision readouts → coach perspective → check-in. Apple
/// Health controls live in the profile (Chunk 7); the hero sync button
/// refreshes health, brief, and decision together.
class _BriefContent extends StatelessWidget {
  const _BriefContent({
    required this.brief,
    required this.targets,
    required this.latestDecision,
    required this.healthHistory,
    required this.syncing,
    required this.onSync,
    required this.onStartSession,
    required this.onViewAnalytics,
    required this.onOpenNutrition,
    required this.onOpenWorkout,
    required this.onCheckIn,
  });

  final DailyBrief brief;
  final Future<NutritionTargets?> targets;
  final Future<CoachDecision?> latestDecision;
  final Future<HealthHistory> healthHistory;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback? onStartSession;
  final VoidCallback? onViewAnalytics;
  final VoidCallback? onOpenNutrition;
  final VoidCallback onOpenWorkout;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroMotionEntrance(
          child: TodayHero(
            brief: brief,
            onStartSession: onStartSession,
            onViewAnalytics: onViewAnalytics,
            onSync: onSync,
            syncing: syncing,
          ),
        ),
        if (brief.computed != null) ...[
          const SizedBox(height: TracendSpacing.lg),
          MicroMotionEntrance(
            delay: MicroMotion.stagger(1),
            child: RecoveryReadoutCard(computed: brief.computed!),
          ),
        ],
        const SizedBox(height: TracendSpacing.lg),
        MicroMotionEntrance(
          delay: MicroMotion.stagger(2),
          child: FutureBuilder<HealthHistory>(
            future: healthHistory,
            builder: (context, snapshot) {
              final history = snapshot.data;
              if (history != null) return TrajectoryTrend(history: history);
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const PremiumGradientCard(
                  child: SizedBox(
                    height: 140,
                    child: Center(child: LinearProgressIndicator()),
                  ),
                );
              }
              return PremiumGradientCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health trend unavailable',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: TracendSpacing.xxs),
                    const Text('Tap Sync to refresh the Apple Health summary.'),
                  ],
                ),
              );
            },
          ),
        ),
        const PrecisionDivider(),
        if (brief.computed != null) ...[
          MicroMotionEntrance(
            delay: MicroMotion.stagger(3),
            child: SleepArchitectureCard(computed: brief.computed!),
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
        MicroMotionEntrance(
          delay: MicroMotion.stagger(4),
          child: SessionPlanCard(
            workout: brief.workout,
            acwr: brief.computed?.scores.acwr,
            onOpen: onOpenWorkout,
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        MicroMotionEntrance(
          delay: MicroMotion.stagger(5),
          child: FutureBuilder<NutritionTargets?>(
            future: targets,
            builder: (context, snapshot) => MetabolicTargetCard(
              consumed: brief.nutrition,
              targets: snapshot.data,
              onLog: onOpenNutrition,
            ),
          ),
        ),
        const SizedBox(height: TracendSpacing.lg),
        MicroMotionEntrance(
          delay: MicroMotion.stagger(6),
          child: _CoachPerspectiveSection(latestDecision: latestDecision),
        ),
        const SizedBox(height: TracendSpacing.lg),
        MicroMotionEntrance(
          delay: MicroMotion.stagger(7),
          child: CheckInPromptBar(
            onCheckIn: onCheckIn,
            completed: brief.checkIn != null,
          ),
        ),
      ],
    );
  }
}

/// Coach perspective: renders the latest [CoachDecision] (carries the real
/// training/nutrition summaries + confidence) to drive the T-Coach/N-Coach
/// toggle. The future is owned by the screen state so the sync-everything
/// pipeline can refresh it after generating a new decision. Falls back to an
/// honest prompt when no decision exists.
class _CoachPerspectiveSection extends StatelessWidget {
  const _CoachPerspectiveSection({required this.latestDecision});

  final Future<CoachDecision?> latestDecision;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoachDecision?>(
      future: latestDecision,
      builder: (context, snapshot) {
        final decision = snapshot.data;
        if (decision == null) {
          return const TracendCard(
            child: Text(
              'Open Coach or tap Sync to generate an evidence-backed daily decision.',
            ),
          );
        }
        return CoachPerspectiveCard(decision: decision);
      },
    );
  }
}
