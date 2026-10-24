import 'dart:async';

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
import 'package:tracend/features/account/region_repository.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
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
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';
import 'package:tracend/shared/plan_changes.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.environment,
    this.onSignOut,
    this.aiConsent,
    this.health,
    this.repositories,
    this.homeWidgets = const MethodChannelHomeWidgetBridge(),
    this.widgetEraser,
    this.userId,
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

  /// The Home Screen and Lock Screen widgets: Today writes their snapshot
  /// here, and a tap on a widget asks this shell for a tab.
  final HomeWidgetBridge homeWidgets;

  /// The one eraser that retries a failed clear of the widgets' snapshot on
  /// launch and resume; its publisher writes again once a retry works. Built
  /// here when not given.
  final HomeWidgetEraser? widgetEraser;

  /// The signed-in athlete, whose Lock Screen widget choice the widgets
  /// follow; null without a backend.
  final String? userId;

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
    this.memory,
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

  /// What Coach remembers; built from the environment when not given.
  final CoachMemoryRepository? memory;
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
  late final CoachMemoryRepository _memory;

  /// Today's morning check-in gate: while it is required, the tab bar gives
  /// way to "Check in to start your day".
  final _checkInGate = CheckInGate();

  /// Announces an approved or undone Coach proposal to the screens that show
  /// the plan, the targets and the goal.
  final _planChanges = PlanChanges();

  /// Writes Today's snapshot for the widgets and keeps the Lock Screen choice.
  late final TodayWidgetPublisher _widgetPublisher = TodayWidgetPublisher(
    bridge: widget.homeWidgets,
    eraser: widget.widgetEraser,
    userId: widget.userId,
  );

  /// Counts the taps on widgets that brought the app forward; Today reloads
  /// on each if its brief is old.
  final _widgetTaps = ValueNotifier<int>(0);

  /// Counts the taps on the workout's Live Activity that ask for the workout
  /// in progress; Train reopens it when no workout screen is open.
  final _workoutRequests = ValueNotifier<int>(0);

  @override
  void dispose() {
    _widgetTaps.dispose();
    _workoutRequests.dispose();
    widget.homeWidgets.stopListeningForTab(_openRequestedTab);
    unawaited(_widgetPublisher.dispose());
    _checkInGate.dispose();
    _planChanges.dispose();
    super.dispose();
  }

  /// Opens what a tap asked for: the tab of a widget (`tracend://today`,
  /// `tracend://train`), or the workout in progress from its Live Activity
  /// (`tracend://workout`). With a workout screen already open the app coming
  /// forward is enough: it shows the logger, and nothing is opened over it.
  Future<void> _openRequestedTab() async {
    final tab = await widget.homeWidgets.takePendingTab();
    if (tab == null || !mounted) return;
    if (tab == HomeWidgetTab.workout && ActiveWorkoutScreen.isOpen) return;
    _widgetTaps.value++;
    if (tab == HomeWidgetTab.workout) _workoutRequests.value++;
    _selectTab(switch (tab) {
      HomeWidgetTab.today => 0,
      HomeWidgetTab.train || HomeWidgetTab.workout => 1,
    });
  }

  @override
  void initState() {
    super.initState();
    widget.homeWidgets.listenForTab(_openRequestedTab);
    unawaited(_openRequestedTab());
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
    _memory =
        injected?.memory ??
        (live
            ? SupabaseCoachMemoryRepository(Supabase.instance.client)
            : const FixtureCoachMemoryRepository());
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
        memory: _memory,
        notifications: widget.environment.hasSupabaseConfiguration
            ? SupabaseNotificationRepository(Supabase.instance.client)
            : const FixtureNotificationRepository(),
        exports: widget.environment.hasSupabaseConfiguration
            ? SupabasePrivacyExportRepository(Supabase.instance.client)
            : const FixturePrivacyExportRepository(),
        deletion: widget.environment.hasSupabaseConfiguration
            ? SupabaseAccountDeletionRepository(Supabase.instance.client)
            : const FixtureAccountDeletionRepository(),
        region: widget.environment.hasSupabaseConfiguration
            ? SupabaseRegionRepository(Supabase.instance.client)
            : const FixtureRegionRepository(),
        aiConsent: widget.aiConsent,
        widgetPublisher: _widgetPublisher,
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
        widgetPublisher: _widgetPublisher,
        widgetTaps: _widgetTaps,
      ),
      () => TrainScreen(
        key: const ValueKey('tab_train'),
        repository: _workouts,
        brief: _brief,
        coach: _coach,
        health: _health,
        onOpenAccount: _openAccount,
        planChanges: _planChanges,
        workoutRequests: _workoutRequests,
      ),
      () => CoachScreen(
        key: const ValueKey('tab_coach'),
        active: _selectedIndex == 2,
        repository: _coach,
        aiConsent: widget.aiConsent,
        proposals: _proposals,
        planChanges: _planChanges,
        memory: _memory,
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
