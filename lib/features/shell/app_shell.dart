import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.environment, this.onSignOut, super.key});

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;

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
  late final DailyBriefRepository _brief;

  @override
  void initState() {
    super.initState();
    _workouts = widget.environment.hasSupabaseConfiguration
        ? SupabaseWorkoutRepository(
            Supabase.instance.client,
            SharedPreferencesAsync(),
          )
        : FixtureWorkoutRepository();
    _health = widget.environment.hasSupabaseConfiguration
        ? SupabaseHealthRepository(
            Supabase.instance.client,
            SharedPreferencesAsync(),
          )
        : const ManualHealthRepository();
    _coach = widget.environment.hasSupabaseConfiguration
        ? SupabaseCoachRepository(Supabase.instance.client)
        : const FixtureCoachRepository();
    _nutrition = widget.environment.hasSupabaseConfiguration
        ? SupabaseNutritionRepository(Supabase.instance.client)
        : const FixtureNutritionRepository();
    _progress = widget.environment.hasSupabaseConfiguration
        ? SupabaseProgressRepository(Supabase.instance.client)
        : const FixtureProgressRepository();
    _brief = widget.environment.hasSupabaseConfiguration
        ? SupabaseDailyBriefRepository(Supabase.instance.client)
        : const FixtureDailyBriefRepository();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <Widget>[
      TodayScreen(
        environment: widget.environment,
        onSignOut: widget.onSignOut,
        workouts: _workouts,
        health: _health,
        coach: _coach,
        brief: _brief,
      ),
      TrainScreen(repository: _workouts),
      CoachScreen(repository: _coach),
      NutritionScreen(repository: _nutrition),
      ProgressScreen(
        repository: _progress,
        training: _workouts is TrainingHubRepository
            ? _workouts as TrainingHubRepository
            : null,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: destinations),
      bottomNavigationBar: _FloatingTabBar(
        selectedIndex: _selectedIndex,
        onSelected: (index) {
          if (index == _selectedIndex) return;
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (
      label: 'Today',
      icon: CupertinoIcons.today,
      selectedIcon: CupertinoIcons.today_fill,
    ),
    (
      label: 'Train',
      icon: CupertinoIcons.bolt,
      selectedIcon: CupertinoIcons.bolt_fill,
    ),
    (
      label: 'Coach',
      icon: CupertinoIcons.bubble_left_bubble_right,
      selectedIcon: CupertinoIcons.bubble_left_bubble_right_fill,
    ),
    (
      label: 'Nutrition',
      icon: CupertinoIcons.chart_pie,
      selectedIcon: CupertinoIcons.chart_pie_fill,
    ),
    (
      label: 'Progress',
      icon: CupertinoIcons.chart_bar,
      selectedIcon: CupertinoIcons.chart_bar_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TracendRadii.navigation),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(TracendRadii.navigation),
                  border: Border.all(
                    color: colors.borderSubtle.withValues(alpha: 0.90),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 70,
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
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      key: ValueKey('tab-${item.label.toLowerCase()}'),
      selected: selected,
      button: true,
      label: '${item.label} tab',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(TracendRadii.navigation),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : TracendMotion.quick,
                  curve: TracendMotion.curve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.actionPrimary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : TracendMotion.quick,
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      key: ValueKey(selected),
                      size: 22,
                      color: selected
                          ? colors.actionPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    height: 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colors.actionPrimary
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
