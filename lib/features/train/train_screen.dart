import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/training_load_gauge.dart';
import 'package:tracend/features/train/widgets/action_cards.dart';
import 'package:tracend/features/train/widgets/prescription_cards.dart';
import 'package:tracend/features/train/widgets/workout_hero.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/intensity_bar.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class TrainScreen extends StatefulWidget {
  const TrainScreen({
    this.repository,
    this.brief,
    this.coach = const FixtureCoachRepository(),
    super.key,
  });
  final WorkoutRepository? repository;
  final DailyBriefRepository? brief;
  final CoachRepository coach;

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  static const _minWeekOffset = -3;

  late final WorkoutRepository _source;
  late Future<TrainingHubData> _hub;
  late Future<DailyBrief> _brief;
  late Future<CoachDecision?> _decision;
  List<WorkoutRepairCandidate> _repairCandidates = const [];
  List<WorkoutReconciliation> _reconciliations = const [];
  String? _reconciliationBusyId;
  final Set<String> _respondedReconciliationIds = {};
  final Set<String> _respondedRepairSessionIds = {};
  int _weekday = DateTime.now().weekday;
  int _weekOffset = 0;
  HealthkitCompletionCandidate? _healthkitCandidate;
  int? _confirmedWorkoutWeekday;
  Future<Map<int, double>>? _recordedRpe;
  String? _recordedRpeKey;

  @override
  void initState() {
    super.initState();
    _source = widget.repository ?? FixtureWorkoutRepository();
    _hub = _load();
    _brief = (widget.brief ?? const FixtureDailyBriefRepository()).load(
      _dateForWeekday(_weekday),
    );
    _decision = widget.coach.loadLatest();
    _fetchHealthkitCandidate();
  }

  Future<TrainingHubData> _load() async {
    final source = _source;
    if (source is WorkoutRepairRepository) {
      final candidates = await (source as WorkoutRepairRepository)
          .loadRepairCandidates();
      _repairCandidates = candidates
          .where((c) => !_respondedRepairSessionIds.contains(c.sessionId))
          .toList();
    }
    if (source is WorkoutReconciliationRepository) {
      final list = await (source as WorkoutReconciliationRepository)
          .loadReconciliations();
      final filtered = list
          .where((r) => !_respondedReconciliationIds.contains(r.id))
          .toList();
      if (list.isNotEmpty || filtered.isNotEmpty) {
        debugPrint(
          'train: loadReconciliations server=${list.length} '
          'filtered=${filtered.length} '
          'excluded_ids=${_respondedReconciliationIds.length}',
        );
      }
      _reconciliations = filtered;
    }
    if (source is TrainingHubRepository) {
      return (source as TrainingHubRepository).loadTrainingHub();
    }
    final workout = await source.loadTodayWorkout();
    return TrainingHubData(
      planTitle: 'Approved plan',
      workouts: [workout],
      recentSessions: const [],
      completedSessions: 0,
      plannedSessions: 0,
      progression: const [],
    );
  }

  Future<void> _confirmRepair(WorkoutRepairCandidate candidate) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct this workout record?'),
        content: Text(
          'Tracend saved ${(candidate.recordedDurationSeconds / 60).round()} minutes, while Apple Health recorded ${(candidate.healthkitDurationSeconds / 60).round()} minutes. Confirming preserves every logged set, changes untouched exercises from skipped to unknown, and audits the correction.${candidate.blankDuplicateSessionId == null ? '' : ' The empty duplicate session will also be abandoned.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm correction'),
          ),
        ],
      ),
    );
    if (accepted != true || _source is! WorkoutRepairRepository) return;
    await (_source as WorkoutRepairRepository).confirmRepair(candidate);
    if (!mounted) return;
    setState(() {
      _respondedRepairSessionIds.add(candidate.sessionId);
      _repairCandidates = _repairCandidates
          .where((c) => c.sessionId != candidate.sessionId)
          .toList();
      _hub = _load();
    });
  }

  Future<void> _respondToReconciliation(
    WorkoutReconciliation item, {
    required bool accept,
  }) async {
    debugPrint(
      'train: respondToReconciliation id=${item.id} accept=$accept '
      'responded_ids_before=${_respondedReconciliationIds.length}',
    );
    setState(() => _reconciliationBusyId = item.id);
    try {
      await (_source as WorkoutReconciliationRepository)
          .respondToReconciliation(item.id, accept: accept);
      debugPrint('train: respondToReconciliation RPC succeeded');
      if (!mounted) return;
      final confirmedWeekday = item.localDate.weekday;
      setState(() {
        _respondedReconciliationIds.add(item.id);
        _reconciliations = _reconciliations
            .where((candidate) => candidate.id != item.id)
            .toList();
        _reconciliationBusyId = null;
        _confirmedWorkoutWeekday = confirmedWeekday;
        _hub = _load();
      });
      debugPrint(
        'train: respondToReconciliation complete '
        'responded_ids_after=${_respondedReconciliationIds.length} '
        'reconciliations=${_reconciliations.length}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Workout match confirmed' : 'Match dismissed'),
        ),
      );
    } catch (error) {
      debugPrint('train: respondToReconciliation RPC failed: $error');
      if (!mounted) return;
      setState(() => _reconciliationBusyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this match. Try again.')),
      );
    }
  }

  Future<void> _autoComplete(HealthkitCompletionCandidate candidate) async {
    try {
      await (_source as SupabaseWorkoutRepository).autoCompleteFromHealthKit(
        candidate.plannedWorkoutId,
        candidate.localDate.toIso8601String().substring(0, 10),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout marked complete from Apple Health'),
        ),
      );
      setState(() {
        _hub = _load();
        _healthkitCandidate = null;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save completion. Try again.')),
      );
    }
  }

  DateTime _dateForWeekday(int weekday) {
    final monday = mondayOf(DateTime.now());
    return monday
        .add(Duration(days: _weekOffset * 7))
        .add(Duration(days: weekday - 1));
  }

  Future<void> _fetchHealthkitCandidate() async {
    if (_source is! HealthkitCandidateRepository) return;
    final requestedWeekday = _weekday;
    final requestedOffset = _weekOffset;
    final date = _dateForWeekday(requestedWeekday);
    final candidate = await (_source as HealthkitCandidateRepository)
        .getHealthkitCandidate(date);
    if (!mounted ||
        _weekday != requestedWeekday ||
        _weekOffset != requestedOffset) {
      return;
    }
    setState(() => _healthkitCandidate = candidate);
  }

  /// Cached recorded-RPE load for the selected completed day. The key guard
  /// makes repeated calls return the same future, so build stays pure.
  Future<Map<int, double>> _recordedRpeFor(
    PlannedWorkout workout,
    DateTime date,
  ) {
    final key = '${workout.id}@${date.toIso8601String().substring(0, 10)}';
    if (key != _recordedRpeKey || _recordedRpe == null) {
      _recordedRpeKey = key;
      _recordedRpe = _loadRecordedRpe(workout, date);
    }
    return _recordedRpe!;
  }

  Future<Map<int, double>> _loadRecordedRpe(
    PlannedWorkout workout,
    DateTime date,
  ) async {
    final session = await _source.loadSession(workout, localDate: date);
    final exercises = session?['exercises'];
    if (exercises is! List) return const {};
    final byOrder = <int, double>{};
    for (final item in exercises) {
      final exercise = Map<String, dynamic>.from(item as Map);
      final order = (exercise['order'] as num?)?.toInt();
      final sets = exercise['sets'];
      if (order == null || sets is! List) continue;
      final values = sets
          .map((set) => (Map<String, dynamic>.from(set as Map))['rpe'])
          .whereType<num>()
          .map((rpe) => rpe.toDouble())
          .where((rpe) => rpe >= 1 && rpe <= 10)
          .toList();
      if (values.isEmpty) continue;
      byOrder[order] = values.reduce((a, b) => a + b) / values.length;
    }
    return byOrder;
  }

  void _selectWeekday(int day) {
    if (day == _weekday) return;
    setState(() {
      _weekday = day;
      _healthkitCandidate = null;
      _recordedRpe = null;
      _recordedRpeKey = null;
      _brief = (widget.brief ?? const FixtureDailyBriefRepository()).load(
        _dateForWeekday(day),
      );
    });
    _fetchHealthkitCandidate();
  }

  void _selectDate(DateTime date) => _selectWeekday(date.weekday);

  void _shiftWeek(int weeks) {
    final next = (_weekOffset + weeks).clamp(_minWeekOffset, 0);
    if (next == _weekOffset) return;
    setState(() {
      _weekOffset = next;
      _healthkitCandidate = null;
      _recordedRpe = null;
      _recordedRpeKey = null;
      _brief = (widget.brief ?? const FixtureDailyBriefRepository()).load(
        _dateForWeekday(_weekday),
      );
    });
    _fetchHealthkitCandidate();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TrainingHubData>(
    future: _hub,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const TracendScrollView(
          title: 'Train',
          subtitle: 'Loading your approved plan',
          children: [LinearProgressIndicator(minHeight: 3)],
        );
      }
      if (snapshot.hasError || snapshot.data == null) {
        return TracendScrollView(
          title: 'Train',
          subtitle: 'Approved plan unavailable',
          children: [
            TracendCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your training plan could not be loaded. No fixture workout was substituted.',
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  OutlinedButton(
                    onPressed: () => setState(() => _hub = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      final hub = snapshot.data!;
      final workout = hub.workoutForWeekday(_weekday);
      final sessionDate = _dateForWeekday(_weekday);
      final isCompleted = hub.isDayCompleted(sessionDate);
      return TracendScrollView(
        title: 'Train',
        subtitle: hub.planTitle,
        children: [
          DatePillStrip(
            selectedDate: sessionDate,
            onSelectedDate: _selectDate,
            daysWithData: hub.completedDays,
            plannedDates: {
              for (final item in hub.workouts)
                if (item.weekday != null) _dateForWeekday(item.weekday!),
            },
            markedDate: _confirmedWorkoutWeekday == null
                ? null
                : _dateForWeekday(_confirmedWorkoutWeekday!),
            onPreviousWeek: _weekOffset > _minWeekOffset
                ? () => _shiftWeek(-1)
                : null,
            onNextWeek: _weekOffset < 0 ? () => _shiftWeek(1) : null,
          ),
          const SizedBox(height: TracendSpacing.md),
          FutureBuilder<DailyBrief>(
            future: _brief,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data?.computed != null) {
                return Column(
                  children: [
                    TrainingLoadGauge(computed: snapshot.data!.computed!),
                    const SizedBox(height: TracendSpacing.md),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (_repairCandidates.isNotEmpty) ...[
            WorkoutRepairCard(
              candidate: _repairCandidates.first,
              onConfirm: () => _confirmRepair(_repairCandidates.first),
            ),
            const SizedBox(height: TracendSpacing.md),
          ],
          if (_reconciliations.isNotEmpty) ...[
            ReconciliationCard(
              item: _reconciliations.first,
              busy: _reconciliationBusyId == _reconciliations.first.id,
              isDifferentDay:
                  _reconciliations.first.localDate.weekday != _weekday,
              onAccept: () => _respondToReconciliation(
                _reconciliations.first,
                accept: true,
              ),
              onReject: () => _respondToReconciliation(
                _reconciliations.first,
                accept: false,
              ),
            ),
            const SizedBox(height: TracendSpacing.md),
          ],
          if (workout == null)
            const RestDayCard()
          else ...[
            if (_healthkitCandidate != null)
              HealthkitCompleteCard(
                candidate: _healthkitCandidate!,
                onComplete: () => _autoComplete(_healthkitCandidate!),
                onManual: () => Navigator.of(context)
                    .push<bool>(
                      CupertinoPageRoute(
                        builder: (_) => WorkoutDetailScreen(
                          repository: _source,
                          workout: workout,
                          sessionDate: _healthkitCandidate!.localDate,
                        ),
                      ),
                    )
                    .then((completed) {
                      if (completed == true) {
                        setState(() {
                          _hub = _load();
                          _healthkitCandidate = null;
                        });
                      }
                    }),
              )
            else
              FutureBuilder<CoachDecision?>(
                future: _decision,
                builder: (context, snapshot) => WorkoutHero(
                  workout: workout,
                  source: _source,
                  sessionDate: sessionDate,
                  isCompleted: isCompleted,
                  coachInsight: snapshot.data?.trainingSummary,
                  onWorkoutChanged: () => setState(() {
                    _hub = _load();
                    _healthkitCandidate = null;
                  }),
                ),
              ),
            const SizedBox(height: TracendSpacing.sm),
            FutureBuilder<DailyBrief>(
              future: _brief,
              builder: (context, snapshot) {
                final strain = snapshot.data?.computed?.scores.dailyStrain;
                if (!isCompleted) {
                  return IntensityBar(
                    entries: [
                      for (final exercise in workout.exercises)
                        IntensityBarEntry(
                          name: exercise.name,
                          targetRpe: exercise.targetRpe,
                        ),
                    ],
                    dailyStrain: strain,
                  );
                }
                return FutureBuilder<Map<int, double>>(
                  future: _recordedRpeFor(workout, sessionDate),
                  builder: (context, rpeSnapshot) {
                    final recorded = rpeSnapshot.data ?? const {};
                    return IntensityBar(
                      entries: [
                        for (final exercise in workout.exercises)
                          IntensityBarEntry(
                            name: exercise.name,
                            targetRpe: exercise.targetRpe,
                            recordedRpe: recorded[exercise.order],
                          ),
                      ],
                      dailyStrain: strain,
                    );
                  },
                );
              },
            ),
            const SectionLabel('Prescription'),
            PrescriptionCard(workout: workout),
            if (workout.warmUp.isNotEmpty ||
                workout.cooldownCardio.isNotEmpty) ...[
              const SizedBox(height: TracendSpacing.sm),
              WarmUpCard(workout: workout),
            ],
          ],
          const SectionLabel('Execution evidence'),
          AdherenceCard(
            completedSessions: hub.completedSessions,
            plannedSessions: hub.plannedSessions,
          ),
          const SizedBox(height: TracendSpacing.sm),
          ProgressionCard(progression: hub.progression),
          if (hub.recentSessions.isNotEmpty) ...[
            const SectionLabel('Recent sessions'),
            RecentSessionsCard(
              sessions: hub.recentSessions.take(6).toList(),
              workoutForId: (id) {
                for (final candidate in hub.workouts) {
                  if (candidate.id == id) return candidate;
                }
                return null;
              },
              repository: _source,
            ),
          ],
        ],
      );
    },
  );
}
