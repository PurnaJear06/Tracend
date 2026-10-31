import 'package:flutter/foundation.dart';

/// Announces that the athlete's training plan, nutrition targets or goal
/// changed (a Coach proposal was approved or undone), so the screens that show
/// them reload. The shell owns one and hands it to those screens and to the
/// Coach chat; a screen without one never reloads on its own.
class PlanChanges extends ChangeNotifier {
  void announce() => notifyListeners();
}

/// Announces that a workout was logged outside Train (Today's "Save workout"
/// on a session left unfinished), so Train reloads its week and history.
class WorkoutLogChanges extends ChangeNotifier {
  void announce() => notifyListeners();
}
