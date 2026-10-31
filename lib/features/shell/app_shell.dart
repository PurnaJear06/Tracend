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
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/shell/floating_tab_bar.dart';
import 'package:tracend/features/shell/offline_tabs.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/guidance/training_guidance_controller.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';
import 'package:tracend/shared/coach_draft_requests.dart';
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
    this.offline = false,
    this.onRetryConnection,
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

  /// The app is open on the plan this phone saved because the account could
  /// not be checked. Train works from the saved plan and the workout can be
  /// logged; Today, Coach, Meals and Progress say they need a connection.
  /// The app opens on Train.
  final bool offline;

  /// Checks the connection again; the gate leaves offline mode when it
  /// works. Null where the app is never offline.
  final Future<void> Function()? onRetryConnection;

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
    this.dayAdjustment,
    this.guidance,
    this.painCheck,
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

  /// Today's same-day readiness adjustment; built from the environment (and
  /// absent without a backend) when not given.
  final DayAdjustmentRepository? dayAdjustment;

  /// Today's training guidance (the lighter-week card, the cardio row); built
  /// from the environment (and absent without a backend) when not given.
  final TrainingGuidanceRepository? guidance;

  /// Sends the pain check made during a workout; built from the environment
  /// (nothing can be sent without a backend) when not given.
  final PainCheckRepository? painCheck;
}

class _AppShellState extends State<AppShell> {
  /// Today is the launch tab, Train when the app opens offline.
  late int _selectedIndex = widget.offline ? 1 : 0;

  /// Tabs opened at least once. A tab is built, and so starts its reads, the
  /// first time it is selected and stays built after that so it keeps its
  /// scroll position and state.
  late final Set<int> _opened = {_selectedIndex};
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

  /// Today's same-day readiness adjustment, shared by Today and Train. Null
  /// without a backend, where there is no readiness to read.
  late final DayAdjustmentController? _dayAdjustment;

  /// Today's training guidance for Train. Null without a backend.
  late final TrainingGuidanceController? _guidance;

  /// Sends the pain reports made during a workout and keeps the ones that
  /// cannot go yet.
  late final PainReporting _pain;

  /// Questions left for the Coach composer by other screens.
  final _coachDrafts = CoachDraftRequests();

  /// Today's morning check-in gate: while it is required, the tab bar gives
  /// way to "Check in to start your day".
  final _checkInGate = CheckInGate();

  /// Announces an approved or undone Coach proposal to the screens that show
  /// the plan, the targets and the goal.
  final _planChanges = PlanChanges();

  /// Announces a workout Today saved from an unfinished session, so Train
  /// reloads its week.
  final _workoutLogs = WorkoutLogChanges();

  /// Counts the taps on Today's session card; Train then selects today.
  final _showTrainToday = ValueNotifier<int>(0);

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

  /// The open workout Today's Resume card asked for; Train reopens it.
  final _resumeRequests = ResumeRequests();

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The connection is back: the screens that showed the saved plan or said
    // they need a connection load for real.
    if (oldWidget.offline && !widget.offline) _planChanges.announce();
  }

  @override
  void dispose() {
    _widgetTaps.dispose();
    _workoutRequests.dispose();
    _resumeRequests.dispose();
    widget.homeWidgets.stopListeningForTab(_openRequestedTab);
    unawaited(_widgetPublisher.dispose());
    _checkInGate.dispose();
    _planChanges.dispose();
    _workoutLogs.dispose();
    _showTrainToday.dispose();
    _dayAdjustment?.dispose();
    _guidance?.dispose();
    _coachDrafts.dispose();
    super.dispose();
  }

  /// Keeps what the server says about sore areas beside the saved plan, so
  /// Train can still say it with no connection.
  void _keepSafetyNotes(DayAdjustment adjustment) {
    final workouts = _workouts;
    final owner = _signedInAtStart;
    if (workouts is SavedSafetyNotesRepository && owner != null) {
      unawaited(
        (workouts as SavedSafetyNotesRepository).saveSafetyNotes(
          adjustment,
          userId: owner,
        ),
      );
    }
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

  /// The athlete this shell opened for. A day adjustment that answers after
  /// another athlete signed in is kept for this one or not at all.
  late final String? _signedInAtStart;

  @override
  void initState() {
    super.initState();
    _signedInAtStart = widget.userId;
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
                loggerOpen: () => ActiveWorkoutScreen.isOpen,
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
    final dayAdjustments =
        injected?.dayAdjustment ??
        (live
            ? SupabaseDayAdjustmentRepository(Supabase.instance.client)
            : null);
    _dayAdjustment = dayAdjustments == null
        ? null
        : DayAdjustmentController(
            repository: dayAdjustments,
            serverToday: _serverToday,
            onAnswered: _keepSafetyNotes,
          );
    final guidance =
        injected?.guidance ??
        (live
            ? SupabaseTrainingGuidanceRepository(Supabase.instance.client)
            : null);
    _guidance = guidance == null
        ? null
        : TrainingGuidanceController(
            repository: guidance,
            serverToday: _serverToday,
          );
    _pain = PainReporting(
      repository:
          injected?.painCheck ??
          (live
              ? SupabasePainCheckRepository(Supabase.instance.client)
              : const OfflinePainCheckRepository()),
      readiness: _dayAdjustment,
      userId: widget.userId,
      // Queued reports go only while their own athlete is signed in.
      signedInUser: live
          ? () => Supabase.instance.client.auth.currentUser?.id
          : null,
    );
    _brief = SharedDailyBriefRepository(
      injected?.brief ??
          (live
              ? SupabaseDailyBriefRepository(Supabase.instance.client)
              : const FixtureDailyBriefRepository()),
    );
  }

  /// The athlete's own today as the server counts it (the training hub's
  /// `local_today`): the only day the readiness adjustment can be read or
  /// answered for. Null when the hub cannot say.
  Future<DateTime?> _serverToday() async {
    final source = _workouts;
    if (source is! TrainingHubRepository) return null;
    final hub = await (source as TrainingHubRepository).loadTrainingHub(
      periodDays: 7,
    );
    // A saved copy names the phone's day, not the server's.
    return hub.cachedAt == null ? hub.localToday : null;
  }

  /// "Talk to Coach" on the readiness card: opens Coach with [question] in the
  /// box. The athlete sends it.
  void _talkToCoach(String question) {
    _coachDrafts.request(question);
    _selectTab(2);
  }

  /// Today's session card: Train opens on today, not on the day last viewed.
  void _openTrainToday() {
    _showTrainToday.value++;
    _selectTab(1);
  }

  /// "Check in" from a screen other than Today: Today owns the sheet.
  void _openCheckIn() {
    _selectTab(0);
    _checkInGate.checkIn();
  }

  Future<void> _retryConnection() async => widget.onRetryConnection?.call();

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

  /// Today's Resume card: Train opens the workout it named.
  void _resumeInTrain(OpenWorkout workout) {
    _resumeRequests.request(workout);
    _selectTab(1);
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _opened.add(index);
    });
  }

  Widget _offlineTab(String key, String title, String needs) => OfflineTab(
    key: ValueKey(key),
    title: title,
    needs: needs,
    onOpenTrain: () => _selectTab(1),
    onRetry: _retryConnection,
  );

  @override
  Widget build(BuildContext context) {
    final destinations = <Widget Function()>[
      () => widget.offline
          ? OfflineToday(
              key: const ValueKey('tab_today_offline'),
              onOpenTrain: () => _selectTab(1),
              onOpenAccount: _openAccount,
              onRetry: _retryConnection,
            )
          : TodayScreen(
              key: const ValueKey('tab_today'),
              environment: widget.environment,
              onSignOut: widget.onSignOut,
              workouts: _workouts,
              health: _health,
              coach: _coach,
              brief: _brief,
              nutrition: _nutrition,
              onOpenNutrition: () => _selectTab(3),
              onOpenTrain: _openTrainToday,
              workoutLogs: _workoutLogs,
              aiConsent: widget.aiConsent,
              checkInGate: _checkInGate,
              planChanges: _planChanges,
              widgetPublisher: _widgetPublisher,
              widgetTaps: _widgetTaps,
              dayAdjustment: _dayAdjustment,
              onTalkToCoach: _talkToCoach,
              pain: _pain,
              userId: widget.userId,
              onResumeWorkout: _resumeInTrain,
              active: _selectedIndex == 0,
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
        resumeRequests: _resumeRequests,
        dayAdjustment: _dayAdjustment,
        guidance: _guidance,
        proposals: _proposals,
        onTalkToCoach: _talkToCoach,
        onCheckIn: _openCheckIn,
        active: _selectedIndex == 1,
        workoutLogs: _workoutLogs,
        showToday: _showTrainToday,
        onRetryConnection: widget.offline ? _retryConnection : null,
        pain: _pain,
      ),
      () => widget.offline
          ? _offlineTab('tab_coach_offline', 'Coach', 'Coach')
          : CoachScreen(
              key: const ValueKey('tab_coach'),
              active: _selectedIndex == 2,
              repository: _coach,
              aiConsent: widget.aiConsent,
              proposals: _proposals,
              planChanges: _planChanges,
              memory: _memory,
              draftRequests: _coachDrafts,
            ),
      () => widget.offline
          ? _offlineTab('tab_nutrition_offline', 'Meals', 'Meals')
          : NutritionScreen(
              key: const ValueKey('tab_nutrition'),
              repository: _nutrition,
              coach: _coach,
              planChanges: _planChanges,
              active: _selectedIndex == 3,
            ),
      () => widget.offline
          ? _offlineTab('tab_progress_offline', 'Progress', 'Progress')
          : ProgressScreen(
              key: const ValueKey('tab_progress'),
              repository: _progress,
              training: _workouts is TrainingHubRepository
                  ? _workouts as TrainingHubRepository
                  : null,
              brief: _brief,
              physique: _physique,
              goalTargets: _goalTargets,
              active: _selectedIndex == 4,
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
