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
    super.key,
  });
  final PlannedWorkout workout;
  final WorkoutRepository repository;
  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  late final List<List<_SetDraft>> _sets;
  String? _sessionId;
  late String _idempotencyKey;
  int _revision = 0;
  bool _syncing = false;
  bool _offline = false;
  final _startedAt = DateTime.now();
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _sets = [
      for (final e in widget.workout.exercises)
        [for (var i = 0; i < e.setCount; i++) _SetDraft()],
    ];
    _restoreAndStart();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreAndStart() async {
    final saved = await widget.repository.loadDraft();
    if (saved != null) {
      final d = decodeDraft(saved);
      _sessionId = d['session_id'] as String?;
      _idempotencyKey = d['idempotency_key'] as String;
      _revision = d['revision'] as int? ?? 0;
      final exercises = d['exercises'] as List? ?? [];
      for (var i = 0; i < exercises.length && i < _sets.length; i++) {
        final rows = (exercises[i] as Map)['sets'] as List;
        for (var j = 0; j < rows.length && j < _sets[i].length; j++) {
          _sets[i][j] = _SetDraft.fromMap(
            Map<String, dynamic>.from(rows[j] as Map),
          );
        }
      }
    } else {
      _idempotencyKey = newIdempotencyKey();
    }
    try {
      _sessionId ??= await widget.repository.start(
        widget.workout,
        _idempotencyKey,
      );
    } catch (_) {
      _offline = true;
      _sessionId ??= 'pending-$_idempotencyKey';
    }
    await _save();
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _draft() => {
    'session_id': _sessionId,
    'idempotency_key': _idempotencyKey,
    'revision': _revision,
    'exercises': [
      for (var i = 0; i < _sets.length; i++)
        {
          'order': widget.workout.exercises[i].order,
          'pain_flag': false,
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
    await widget.repository.saveDraft(jsonEncode(draft));
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
        Navigator.pop(context);
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
                onChanged: _changed,
              ),
            ],
            const SizedBox(height: TracendSpacing.md),
            const ComingSoonButton(
              label: 'Pain or discomfort',
              detail:
                  'Pain flagging is planned for the next workout-safety slice.',
              icon: CupertinoIcons.waveform_path_ecg,
            ),
            const SizedBox(height: TracendSpacing.lg),
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
    required this.onChanged,
  });
  final PlannedExercise exercise;
  final List<_SetDraft> sets;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(
        '${exercise.order.toString().padLeft(2, '0')} · ${exercise.name}',
      ),
      Text(
        '${exercise.setCount} × ${exercise.repMin}–${exercise.repMax} · RPE ${exercise.targetRpe}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: TracendSpacing.sm),
      TracendCard(
        raised: true,
        child: Column(
          children: [
            for (var i = 0; i < sets.length; i++) ...[
              _SetRow(number: i + 1, draft: sets[i], onChanged: onChanged),
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
    required this.onChanged,
  });
  final int number;
  final _SetDraft draft;
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'kg'),
          onChanged: (v) {
            draft.load = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextFormField(
          initialValue: draft.reps,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'reps'),
          onChanged: (v) {
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
          onPressed: () {
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
  _SetDraft({this.load = '', this.reps = '', this.completed = false});
  String load;
  String reps;
  bool completed;
  Map<String, dynamic> toMap() => {
    'load_kg': load,
    'repetitions': reps,
    'rpe': '',
    'completed': completed,
  };
  factory _SetDraft.fromMap(Map<String, dynamic> m) => _SetDraft(
    load: '${m['load_kg'] ?? ''}',
    reps: '${m['repetitions'] ?? ''}',
    completed: m['completed'] == true,
  );
}
