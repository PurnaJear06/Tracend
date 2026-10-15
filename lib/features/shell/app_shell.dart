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
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/shell/floating_tab_bar.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.environment,
    this.onSignOut,
    this.aiConsent,
    this.health,
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  late final WorkoutRepository _workouts;
  late final HealthRepository _health;
  late final CoachRepository _coach;
  late final NutritionRepository _nutrition;
  late final ProgressRepository _progress;
  late final PhysiqueCheckRepository _physique;
  late final DailyBriefRepository _brief;

  /// Today's morning check-in gate: while it is required, the tab bar gives
  /// way to "Check in to start your day".
  final _checkInGate = CheckInGate();

  @override
  void dispose() {
    _checkInGate.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _workouts = widget.environment.hasSupabaseConfiguration
        ? SupabaseWorkoutRepository(
            Supabase.instance.client,
            SharedPreferencesAsync(),
          )
        : FixtureWorkoutRepository();
    _health =
        widget.health ??
        (widget.environment.hasSupabaseConfiguration
            ? SupabaseHealthRepository(
                Supabase.instance.client,
                SharedPreferencesAsync(),
              )
            : const ManualHealthRepository());
    _coach = widget.environment.hasSupabaseConfiguration
        ? SupabaseCoachRepository(Supabase.instance.client)
        : const FixtureCoachRepository();
    _nutrition = widget.environment.hasSupabaseConfiguration
        ? SupabaseNutritionRepository(Supabase.instance.client)
        : const FixtureNutritionRepository();
    _progress = widget.environment.hasSupabaseConfiguration
        ? SupabaseProgressRepository(Supabase.instance.client)
        : const FixtureProgressRepository();
    _physique = widget.environment.hasSupabaseConfiguration
        ? SupabasePhysiqueCheckRepository(Supabase.instance.client)
        : const FixturePhysiqueCheckRepository();
    _brief = widget.environment.hasSupabaseConfiguration
        ? SharedDailyBriefRepository(
            SupabaseDailyBriefRepository(Supabase.instance.client),
          )
        : const FixtureDailyBriefRepository();
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
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <Widget>[
      TodayScreen(
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
      ),
      TrainScreen(
        key: const ValueKey('tab_train'),
        repository: _workouts,
        brief: _brief,
        coach: _coach,
        health: _health,
        onOpenAccount: _openAccount,
      ),
      CoachScreen(
        key: const ValueKey('tab_coach'),
        repository: _coach,
        aiConsent: widget.aiConsent,
      ),
      NutritionScreen(
        key: const ValueKey('tab_nutrition'),
        repository: _nutrition,
        coach: _coach,
      ),
      ProgressScreen(
        key: const ValueKey('tab_progress'),
        repository: _progress,
        training: _workouts is TrainingHubRepository
            ? _workouts as TrainingHubRepository
            : null,
        brief: _brief,
        physique: _physique,
      ),
    ];

    return Scaffold(
      // The body runs under the bottom slot, and its bottom padding reports
      // the slot's height, so scroll views end clear of the bar.
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: destinations),
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
