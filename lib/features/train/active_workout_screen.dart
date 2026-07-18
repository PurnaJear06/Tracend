import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({
    required this.workout,
    required this.repository,
    this.sessionDate,
    super.key,
  });
  final PlannedWorkout workout;
  final WorkoutRepository repository;
  final DateTime? sessionDate;
  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  late final List<List<_SetDraft>> _sets;
  late final List<String> _exerciseStatuses;
  late final List<bool> _painFlags;
  String? _sessionId;
  late String _idempotencyKey;
  int _revision = 0;
  bool _syncing = false;
  bool _offline = false;
  bool _isViewingCompleted = false;
  DateTime _startedAt = DateTime.now();
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _sets = [
      for (final e in widget.workout.exercises)
        [for (var i = 0; i < e.setCount; i++) _SetDraft()],
    ];
    _exerciseStatuses = List.filled(widget.workout.exercises.length, 'unknown');
    _painFlags = List.filled(widget.workout.exercises.length, false);
    _restoreAndStart();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreAndStart() async {
    final server = await widget.repository.loadSession(
      widget.workout,
      localDate: widget.sessionDate,
    );
    if (server != null && server['state'] == 'completed') {
      _sessionId = server['session_id'] as String;
      _isViewingCompleted = true;
      final exercises = server['exercises'] as List?;
      if (exercises != null && exercises.isNotEmpty &&
          exercises.first is Map) {
        _hydrateSets(exercises);
      } else {
        _populateFromPlan();
      }
      if (mounted) setState(() {});
      return;
    }
    final saved = await widget.repository.loadDraft(widget.workout.id);
    Map<String, dynamic>? d;
    if (server != null && server['state'] == 'in_progress') {
      d = server;
    } else if (saved != null) {
      d = decodeDraft(saved);
    }
    if (d != null) {
      _sessionId = d['session_id'] as String?;
      _idempotencyKey = d['idempotency_key'] as String? ?? newIdempotencyKey();
      _revision = (d['revision'] as num?)?.toInt() ?? 0;
      _startedAt =
          DateTime.tryParse('${d['actual_started_at'] ?? ''}') ??
          DateTime.now();
      final exercises = d['exercises'] as List? ?? const [];
      _hydrateSets(exercises);
    } else {
      _idempotencyKey = newIdempotencyKey();
    }
    try {
      _sessionId ??= await widget.repository.start(
        widget.workout,
        _idempotencyKey,
        localDate: widget.sessionDate,
      );
    } catch (_) {
      _offline = true;
      _sessionId ??= 'pending-$_idempotencyKey';
    }
    await _save();
    if (mounted) setState(() {});
  }

  void _hydrateSets(List exercises) {
    for (var i = 0; i < exercises.length && i < _sets.length; i++) {
      final exercise = Map<String, dynamic>.from(exercises[i] as Map);
      _exerciseStatuses[i] = exercise['status'] as String? ?? 'unknown';
      _painFlags[i] = exercise['pain_flag'] == true;
      final rows = exercise['sets'] as List? ?? const [];
      for (var j = 0; j < rows.length && j < _sets[i].length; j++) {
        _sets[i][j] = _SetDraft.fromMap(
          Map<String, dynamic>.from(rows[j] as Map),
        );
      }
    }
  }

  void _populateFromPlan() {
    _idempotencyKey = newIdempotencyKey();
  }

  Map<String, dynamic> _draft() => {
    'workout_id': widget.workout.id,
    'session_id': _sessionId,
    'idempotency_key': _idempotencyKey,
    'revision': _revision,
    'exercises': [
      for (var i = 0; i < _sets.length; i++)
        {
          'order': widget.workout.exercises[i].order,
          'status': _exerciseStatuses[i],
          'pain_flag': _painFlags[i],
          'rest_seconds': widget.workout.exercises[i].restSeconds,
          'sets': [
            for (var j = 0; j < _sets[i].length; j++)
              {'number': j + 1, ..._sets[i][j].toMap()},
          ],
        },
    ],
  };
  void _changed() {
    _revision++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _save);
    setState(() {});
  }

  Future<void> _save() async {
    final draft = _draft();
    await widget.repository.saveDraft(widget.workout.id, jsonEncode(draft));
    final id = _sessionId;
    if (id == null || id.startsWith('pending-')) return;
    setState(() => _syncing = true);
    try {
      await widget.repository.sync(id, _revision, draft);
      _offline = false;
    } catch (_) {
      _offline = true;
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _complete() async {
    if (_isViewingCompleted) {
      Navigator.of(context).pop();
      return;
    }
    await _save();
    final id = _sessionId;
    if (id == null || id.startsWith('pending-')) {
      setState(() => _offline = true);
      return;
    }
    try {
      await widget.repository.complete(
        id,
        _revision,
        DateTime.now().difference(_startedAt).inSeconds,
        _draft(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Workout completed')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Completion needs a connection. Your sets remain saved on this device.',
            ),
          ),
        );
      }
    }
  }

  int get _completed => _sets.expand((e) => e).where((s) => s.completed).length;
  int get _totalSets =>
      _sets.fold<int>(0, (total, rows) => total + rows.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final progress = _totalSets == 0 ? 0.0 : _completed / _totalSets;
    return Scaffold(
      appBar: AppBar(title: Text(widget.workout.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.sm,
            TracendSpacing.gutter,
            120,
          ),
          children: [
            if (_isViewingCompleted)
              TracendCard(
                radius: TracendRadii.decision,
                padding: const EdgeInsets.all(TracendSpacing.gutter),
                raised: true,
                child: Row(
                  children: [
                    Icon(CupertinoIcons.info_circle, color: colors.stateStable),
                    const SizedBox(width: TracendSpacing.sm),
                    const Expanded(
                      child: Text(
                        'Auto-completed from Apple Health — no individual sets logged. The planned exercises are shown for reference.',
                      ),
                    ),
                  ],
                ),
              ),
            TracendCard(
              radius: TracendRadii.decision,
              padding: const EdgeInsets.all(TracendSpacing.gutter),
              raised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    label: _offline
                        ? 'Saved on device · sync pending'
                        : _syncing
                        ? 'Saving changes…'
                        : 'Saved and synced',
                    icon: _offline
                        ? CupertinoIcons.wifi_slash
                        : CupertinoIcons.check_mark_circled_solid,
                  ),
                  const SizedBox(height: TracendSpacing.lg),
                  Text(
                    '$_completed sets complete',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  Text(
                    'Entries save automatically. Pain remains reachable before completion.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: TracendSpacing.md),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    color: colors.actionPrimary,
                    backgroundColor: colors.borderSubtle,
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  Text(
                    '$_completed of $_totalSets working sets',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            for (var i = 0; i < widget.workout.exercises.length; i++) ...[
              _ExerciseEditor(
                exercise: widget.workout.exercises[i],
                sets: _sets[i],
                status: _exerciseStatuses[i],
                painFlag: _painFlags[i],
                readOnly: _isViewingCompleted,
                onStatusChanged: (value) {
                  _exerciseStatuses[i] = value;
                  _changed();
                },
                onPainChanged: (value) {
                  _painFlags[i] = value;
                  _changed();
                },
                onChanged: _changed,
              ),
            ],
            const SizedBox(height: TracendSpacing.lg),
            if (_isViewingCompleted)
              FilledButton(
                onPressed: _complete,
                child: const Text('Done'),
              )
            else
              FilledButton(
                onPressed: _completed == 0 ? null : _complete,
                child: const Text('Complete workout'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseEditor extends StatelessWidget {
  const _ExerciseEditor({
    required this.exercise,
    required this.sets,
    required this.status,
    required this.painFlag,
    this.readOnly = false,
    required this.onStatusChanged,
    required this.onPainChanged,
    required this.onChanged,
  });
  final PlannedExercise exercise;
  final List<_SetDraft> sets;
  final String status;
  final bool painFlag;
  final bool readOnly;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<bool> onPainChanged;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(
        '${exercise.order.toString().padLeft(2, '0')} · ${exercise.name}',
      ),
      Text(
        '${exercise.setCount} × ${exercise.repMin}–${exercise.repMax} · RPE ${exercise.targetRpe} · Rest ${exercise.restSeconds}s',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: TracendSpacing.sm),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          FilterChip(
            label: const Text('Skipped intentionally'),
            selected: status == 'skipped',
            onSelected: readOnly
                ? null
                : (selected) =>
                    onStatusChanged(selected ? 'skipped' : 'unknown'),
          ),
          FilterChip(
            label: const Text('Pain or discomfort'),
            selected: painFlag,
            onSelected: readOnly ? null : onPainChanged,
          ),
        ],
      ),
      const SizedBox(height: TracendSpacing.sm),
      TracendCard(
        raised: true,
        child: Column(
          children: [
            for (var i = 0; i < sets.length; i++) ...[
              _SetRow(
                number: i + 1,
                draft: sets[i],
                readOnly: readOnly,
                onChanged: onChanged,
              ),
              if (i < sets.length - 1) const Divider(height: TracendSpacing.md),
            ],
          ],
        ),
      ),
    ],
  );
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.number,
    required this.draft,
    this.readOnly = false,
    required this.onChanged,
  });
  final int number;
  final _SetDraft draft;
  final bool readOnly;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 28,
        child: Text('$number', style: Theme.of(context).textTheme.titleMedium),
      ),
      Expanded(
        child: TextFormField(
          initialValue: draft.load,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'kg'),
          onChanged: readOnly ? null : (v) {
            draft.load = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 64,
        child: TextFormField(
          initialValue: draft.rpe,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'RPE'),
          onChanged: readOnly ? null : (v) {
            draft.rpe = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextFormField(
          initialValue: draft.reps,
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'reps'),
          onChanged: readOnly ? null : (v) {
            draft.reps = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        label: 'Complete set $number',
        button: true,
        child: IconButton.filledTonal(
          onPressed: readOnly ? null : () {
            draft.completed = !draft.completed;
            onChanged();
          },
          icon: Icon(
            draft.completed ? CupertinoIcons.check_mark : CupertinoIcons.circle,
          ),
          tooltip: 'Complete set $number',
        ),
      ),
    ],
  );
}

class _SetDraft {
  _SetDraft({
    this.load = '',
    this.reps = '',
    this.rpe = '',
    this.completed = false,
  });
  String load;
  String reps;
  String rpe;
  bool completed;
  Map<String, dynamic> toMap() => {
    'load_kg': load,
    'repetitions': reps,
    'rpe': rpe,
    'completed': completed,
  };
  factory _SetDraft.fromMap(Map<String, dynamic> m) => _SetDraft(
    load: '${m['load_kg'] ?? ''}',
    reps: '${m['repetitions'] ?? ''}',
    rpe: '${m['rpe'] ?? ''}',
    completed: m['completed'] == true,
  );
}
