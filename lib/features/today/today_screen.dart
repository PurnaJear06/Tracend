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
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/today/check_in_sheet.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/recovery_ring.dart';
import 'package:tracend/features/today/sleep_architecture_card.dart';
import 'package:tracend/features/today/widgets/check_in_prompt_bar.dart';
import 'package:tracend/features/today/widgets/coach_perspective_card.dart';
import 'package:tracend/features/today/widgets/health_evidence_section.dart';
import 'package:tracend/features/today/widgets/metabolic_target_card.dart';
import 'package:tracend/features/today/widgets/precision_divider.dart';
import 'package:tracend/features/today/widgets/readiness_strip.dart';
import 'package:tracend/features/today/widgets/session_plan_card.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

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

  @override
  void initState() {
    super.initState();
    _reloadHealth();
    _targets = widget.nutrition.loadTargets();
    _brief = widget.brief.load(DateTime.now());
  }

  void _reloadHealth() {
    _healthHistory = widget.health.loadHistory();
  }

  void _reloadBriefAndHealth() {
    _reloadHealth();
    setState(() => _brief = widget.brief.load(DateTime.now()));
  }

  Future<void> _openCheckIn() async {
    await showCheckInSheet(context, widget.environment);
    if (mounted) {
      setState(() => _brief = widget.brief.load(DateTime.now()));
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
            return _BriefContent(
              brief: brief,
              targets: _targets,
              coach: widget.coach,
              onStartSession: brief.workout != null ? _openWorkout : null,
              onViewAnalytics: widget.onOpenProgress,
              onOpenNutrition: widget.onOpenNutrition,
              onOpenWorkout: _openWorkout,
              onCheckIn: _openCheckIn,
              onReadinessDetail: _showReadinessDetail,
            );
          },
        ),
        const SectionLabel('Apple Health'),
        HealthStatusCard(
          repository: widget.health,
          onSynced: _reloadBriefAndHealth,
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
            return HealthEvidenceSection(history: snapshot.data!);
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

/// The loaded-brief composition (plan §4.3 layout): hero → recovery ring →
/// readiness strip → evidence → precision readouts → coach perspective.
class _BriefContent extends StatelessWidget {
  const _BriefContent({
    required this.brief,
    required this.targets,
    required this.coach,
    required this.onStartSession,
    required this.onViewAnalytics,
    required this.onOpenNutrition,
    required this.onOpenWorkout,
    required this.onCheckIn,
    required this.onReadinessDetail,
  });

  final DailyBrief brief;
  final Future<NutritionTargets?> targets;
  final CoachRepository coach;
  final VoidCallback? onStartSession;
  final VoidCallback? onViewAnalytics;
  final VoidCallback? onOpenNutrition;
  final VoidCallback onOpenWorkout;
  final VoidCallback onCheckIn;
  final void Function(BuildContext context, String title, String detail)
  onReadinessDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TodayHero(
          brief: brief,
          onStartSession: onStartSession,
          onViewAnalytics: onViewAnalytics,
        ),
        if (brief.computed != null) ...[
          const SizedBox(height: TracendSpacing.lg),
          Center(child: RecoveryRing(computed: brief.computed!)),
        ],
        const SizedBox(height: TracendSpacing.lg),
        ReadinessStrip(
          brief: brief,
          onOpen: (title, detail) => onReadinessDetail(context, title, detail),
        ),
        const SizedBox(height: TracendSpacing.sm),
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
                    brief.nextMeal?['label'] as String? ?? 'No remaining meal',
              ),
            ],
          ),
        ),
        const PrecisionDivider(),
        if (brief.computed != null) ...[
          SleepArchitectureCard(computed: brief.computed!),
          const SizedBox(height: TracendSpacing.sm),
        ],
        SessionPlanCard(workout: brief.workout, onOpen: onOpenWorkout),
        const SizedBox(height: TracendSpacing.sm),
        FutureBuilder<NutritionTargets?>(
          future: targets,
          builder: (context, snapshot) => MetabolicTargetCard(
            consumed: brief.nutrition,
            targets: snapshot.data,
            onLog: onOpenNutrition,
          ),
        ),
        const SizedBox(height: TracendSpacing.lg),
        _CoachPerspectiveSection(coach: coach),
        if (brief.checkIn == null) ...[
          const SizedBox(height: TracendSpacing.lg),
          CheckInPromptBar(onCheckIn: onCheckIn),
        ] else ...[
          const SizedBox(height: TracendSpacing.lg),
          CheckInPromptBar(onCheckIn: onCheckIn, completed: true),
        ],
      ],
    );
  }
}

/// Coach perspective: loads the latest [CoachDecision] (carries the real
/// training/nutrition summaries + confidence) to drive the T-Coach/N-Coach
/// toggle. Falls back to an honest prompt when no decision exists.
class _CoachPerspectiveSection extends StatelessWidget {
  const _CoachPerspectiveSection({required this.coach});

  final CoachRepository coach;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoachDecision?>(
      future: coach.loadLatest(),
      builder: (context, snapshot) {
        final decision = snapshot.data;
        if (decision == null) {
          return const TracendCard(
            child: Text(
              'Open Coach to generate an evidence-backed daily decision.',
            ),
          );
        }
        return CoachPerspectiveCard(decision: decision);
      },
    );
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
