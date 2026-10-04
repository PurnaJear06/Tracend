import 'package:flutter/cupertino.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';

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
        ? SupabaseDailyBriefRepository(Supabase.instance.client)
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
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: destinations),
      bottomNavigationBar: ListenableBuilder(
        listenable: _checkInGate,
        builder: (context, _) {
          final gated = _checkInGate.required && _selectedIndex == 0;
          return AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TracendMotion.emphasized,
            switchInCurve: TracendMotion.curve,
            switchOutCurve: TracendMotion.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: gated
                ? CheckInGateBar(
                    key: const ValueKey('check-in-gate'),
                    onCheckIn: _checkInGate.checkIn,
                    onSkip: _checkInGate.skip,
                  )
                : _FloatingTabBar(
                    key: const ValueKey('tab-bar'),
                    selectedIndex: _selectedIndex,
                    onSelected: _selectTab,
                  ),
          );
        },
      ),
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (
      label: 'Today',
      icon: Icons.wb_sunny_outlined,
      selectedIcon: Icons.wb_sunny_rounded,
    ),
    (
      label: 'Train',
      icon: Icons.fitness_center_rounded,
      selectedIcon: Icons.fitness_center_rounded,
    ),
    (
      label: 'Coach',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    (
      label: 'Nutrition',
      icon: Icons.restaurant_rounded,
      selectedIcon: Icons.restaurant_rounded,
    ),
    (
      label: 'Progress',
      icon: Icons.trending_up_rounded,
      selectedIcon: Icons.trending_up_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 6 : 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: TracendGlass(
              borderRadius: 32,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var index = 0; index < _items.length; index++)
                      Expanded(
                        child: _TabItem(
                          item: _items[index],
                          selected: selectedIndex == index,
                          reduceMotion: reduceMotion,
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.item,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final ({String label, IconData icon, IconData selectedIcon}) item;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final item = widget.item;
    final selected = widget.selected;
    final duration = widget.reduceMotion ? Duration.zero : TracendMotion.quick;
    return Semantics(
      key: ValueKey('tab-${item.label.toLowerCase()}'),
      selected: selected,
      button: true,
      label: '${item.label} tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: duration,
          curve: TracendMotion.curve,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: duration,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey(selected),
                  size: 23,
                  color: selected
                      ? colors.accentSignalInk
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                // iOS tab bars keep labels near-fixed under Dynamic Type;
                // clamp so the label never overflows the 64pt capsule.
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
