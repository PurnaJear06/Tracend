import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/goals/goal_target_repository.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/shell/floating_tab_bar.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/plan_changes.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.environment,
    this.onSignOut,
    this.aiConsent,
    this.health,
    this.repositories,
    super.key,
  });

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;

  /// The AI coaching answer. Null only without a backend, where no data
  /// reaches an AI provider.
  final AiCoachingConsentController? aiConsent;

  /// Apple Health, shared with onboarding so both read one per-athlete state.
  /// Built here when not given.
  final HealthRepository? health;

  /// Replaces the repositories the shell builds from [environment]. Tests use
  /// it to count reads; the app leaves it null.
  @visibleForTesting
  final AppShellRepositories? repositories;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// The repositories the tabs share. Any left null is built from the
/// environment.
@visibleForTesting
class AppShellRepositories {
  const AppShellRepositories({
    this.workouts,
    this.coach,
    this.nutrition,
    this.progress,
    this.physique,
    this.goalTargets,
    this.brief,
    this.proposals,
  });

  final WorkoutRepository? workouts;
  final CoachRepository? coach;
  final NutritionRepository? nutrition;
  final ProgressRepository? progress;
  final PhysiqueCheckRepository? physique;
  final GoalTargetRepository? goalTargets;

  /// The unshared brief repository; the shell shares it between tabs.
  final DailyBriefRepository? brief;

  /// The Coach proposals repository; built from the environment (and absent
  /// without a backend) when not given.
  final CoachProposalRepository? proposals;
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  /// Tabs opened at least once. A tab is built, and so starts its reads, the
  /// first time it is selected and stays built after that so it keeps its
  /// scroll position and state. Today is the launch tab.
  final _opened = <int>{0};
  late final WorkoutRepository _workouts;
  late final HealthRepository _health;
  late final CoachRepository _coach;
  late final NutritionRepository _nutrition;
  late final ProgressRepository _progress;
  late final PhysiqueCheckRepository _physique;
  late final GoalTargetRepository _goalTargets;
  late final DailyBriefRepository _brief;
  late final CoachProposalRepository? _proposals;

  /// Today's morning check-in gate: while it is required, the tab bar gives
  /// way to "Check in to start your day".
  final _checkInGate = CheckInGate();

  /// Announces an approved or undone Coach proposal to the screens that show
  /// the plan, the targets and the goal.
  final _planChanges = PlanChanges();

  @override
  void dispose() {
    _checkInGate.dispose();
    _planChanges.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final injected = widget.repositories;
    final live = widget.environment.hasSupabaseConfiguration;
    _workouts =
        injected?.workouts ??
        (live
            ? SupabaseWorkoutRepository(
                Supabase.instance.client,
                SharedPreferencesAsync(),
              )
            : FixtureWorkoutRepository());
    _health =
        widget.health ??
        (live
            ? SupabaseHealthRepository(
                Supabase.instance.client,
                SharedPreferencesAsync(),
              )
            : const ManualHealthRepository());
    _coach =
        injected?.coach ??
        (live
            ? SupabaseCoachRepository(Supabase.instance.client)
            : const FixtureCoachRepository());
    _proposals =
        injected?.proposals ??
        (live
            ? SupabaseCoachProposalRepository(Supabase.instance.client)
            : null);
    _nutrition =
        injected?.nutrition ??
        (live
            ? SupabaseNutritionRepository(Supabase.instance.client)
            : const FixtureNutritionRepository());
    _progress =
        injected?.progress ??
        (live
            ? SupabaseProgressRepository(Supabase.instance.client)
            : const FixtureProgressRepository());
    _physique =
        injected?.physique ??
        (live
            ? SupabasePhysiqueCheckRepository(Supabase.instance.client)
            : const FixturePhysiqueCheckRepository());
    _goalTargets =
        injected?.goalTargets ??
        (live
            ? SupabaseGoalTargetRepository(Supabase.instance.client)
            : const FixtureGoalTargetRepository());
    _brief = SharedDailyBriefRepository(
      injected?.brief ??
          (live
              ? SupabaseDailyBriefRepository(Supabase.instance.client)
              : const FixtureDailyBriefRepository()),
    );
  }

  /// Account opened from a screen without its own route to it (Train's
  /// "Connect Apple Health"). Today's avatar opens the same screen.
  void _openAccount() => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => AccountScreen(
        environment: widget.environment,
        onSignOut: widget.onSignOut,
        health: _health,
        coach: _coach,
        notifications: widget.environment.hasSupabaseConfiguration
            ? SupabaseNotificationRepository(Supabase.instance.client)
            : const FixtureNotificationRepository(),
        exports: widget.environment.hasSupabaseConfiguration
            ? SupabasePrivacyExportRepository(Supabase.instance.client)
            : const FixturePrivacyExportRepository(),
        deletion: widget.environment.hasSupabaseConfiguration
            ? SupabaseAccountDeletionRepository(Supabase.instance.client)
            : const FixtureAccountDeletionRepository(),
        aiConsent: widget.aiConsent,
      ),
    ),
  );

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _opened.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <Widget Function()>[
      () => TodayScreen(
        key: const ValueKey('tab_today'),
        environment: widget.environment,
        onSignOut: widget.onSignOut,
        workouts: _workouts,
        health: _health,
        coach: _coach,
        brief: _brief,
        nutrition: _nutrition,
        onOpenNutrition: () => _selectTab(3),
        onOpenTrain: () => _selectTab(1),
        aiConsent: widget.aiConsent,
        checkInGate: _checkInGate,
        planChanges: _planChanges,
      ),
      () => TrainScreen(
        key: const ValueKey('tab_train'),
        repository: _workouts,
        brief: _brief,
        coach: _coach,
        health: _health,
        onOpenAccount: _openAccount,
        planChanges: _planChanges,
      ),
      () => CoachScreen(
        key: const ValueKey('tab_coach'),
        repository: _coach,
        aiConsent: widget.aiConsent,
        proposals: _proposals,
        planChanges: _planChanges,
      ),
      () => NutritionScreen(
        key: const ValueKey('tab_nutrition'),
        repository: _nutrition,
        coach: _coach,
        planChanges: _planChanges,
      ),
      () => ProgressScreen(
        key: const ValueKey('tab_progress'),
        repository: _progress,
        training: _workouts is TrainingHubRepository
            ? _workouts as TrainingHubRepository
            : null,
        brief: _brief,
        physique: _physique,
        goalTargets: _goalTargets,
      ),
    ];

    final tabs = [
      for (var i = 0; i < destinations.length; i++)
        _opened.contains(i) ? destinations[i]() : const SizedBox.shrink(),
    ];

    return Scaffold(
      // The body runs under the bottom slot, and its bottom padding reports
      // the slot's height, so scroll views end clear of the bar.
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: FloatingBarFrame(
        child: ListenableBuilder(
          listenable: _checkInGate,
          builder: (context, _) => FloatingBarSwitcher(
            child: _checkInGate.required && _selectedIndex == 0
                ? CheckInGateBar(
                    key: const ValueKey('check-in-gate'),
                    onCheckIn: _checkInGate.checkIn,
                    onSkip: _checkInGate.skip,
                  )
                : FloatingTabBar(
                    key: const ValueKey('tab-bar'),
                    selectedIndex: _selectedIndex,
                    onSelected: _selectTab,
                  ),
          ),
        ),
      ),
    );
  }
}
