import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/goals/goal_target.dart';
import 'package:tracend/features/goals/goal_target_repository.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

enum _Kind { weight, bodyFat, physique }

/// The form behind "Set your target": one kind of target (a weight, a
/// body-fat range or a physique goal) and an optional date. [onSave] runs the
/// write; the sheet closes with its result, and a refusal stays on screen
/// beside the Save button.
class GoalTargetSheet extends StatefulWidget {
  const GoalTargetSheet({
    required this.onSave,
    this.initial = const GoalTarget(),
    this.minWeightKg,
    super.key,
  });

  final Future<GoalTargetState> Function(GoalTarget target) onSave;
  final GoalTarget initial;

  /// The lowest weight the server accepts for this athlete, when known.
  final double? minWeightKg;

  @override
  State<GoalTargetSheet> createState() => _GoalTargetSheetState();
}

class _GoalTargetSheetState extends State<GoalTargetSheet> {
  final _form = GlobalKey<FormState>();
  late _Kind _kind;
  final _weight = TextEditingController();
  final _fatMin = TextEditingController();
  final _fatMax = TextEditingController();
  final _note = TextEditingController();
  String? _physique;
  DateTime? _date;
  bool _saving = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial.weightKg != null
        ? _Kind.weight
        : initial.hasBodyFat
        ? _Kind.bodyFat
        : initial.physique != null
        ? _Kind.physique
        : _Kind.weight;
    _weight.text = initial.weightKg?.toString() ?? '';
    _fatMin.text = initial.bodyFatMinPct?.toString() ?? '';
    _fatMax.text = initial.bodyFatMaxPct?.toString() ?? '';
    _note.text = initial.physiqueNote ?? '';
    _physique = initial.physique;
    _date = initial.date;
  }

  @override
  void dispose() {
    _weight.dispose();
    _fatMin.dispose();
    _fatMax.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  GoalTarget _target() => switch (_kind) {
    _Kind.weight => GoalTarget(weightKg: _number(_weight), date: _date),
    _Kind.bodyFat => GoalTarget(
      bodyFatMinPct: _number(_fatMin),
      bodyFatMaxPct: _number(_fatMax),
      date: _date,
    ),
    _Kind.physique => GoalTarget(
      physique: _physique,
      physiqueNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      date: _date,
    ),
  };

  String? _weightError(String? _) {
    final kg = _number(_weight);
    if (kg == null || kg < 30 || kg > 300) return 'Enter a weight in kg';
    final floor = widget.minWeightKg;
    if (floor != null && kg < floor) {
      return 'Lowest healthy target for your height is '
          '${floor.toStringAsFixed(1)} kg';
    }
    return null;
  }

  String? _fatError(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) {
      return _fatMin.text.trim().isEmpty && _fatMax.text.trim().isEmpty
          ? 'Enter at least one value'
          : null;
    }
    final value = _number(controller);
    if (value == null || value < 3 || value > 60) return 'Between 3 and 60';
    final low = _number(_fatMin);
    final high = _number(_fatMax);
    if (low != null && high != null && low > high) {
      return 'Low must not be above high';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today.add(const Duration(days: 90)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 1095)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_kind == _Kind.physique && _physique == null) {
      setState(() => _problem = 'Choose the look you are aiming for.');
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final saved = await widget.onSave(_target());
      if (mounted) Navigator.pop(context, saved);
    } on GoalTargetException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = error.message;
        });
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _problem =
              'Could not save your target. Check your connection and try '
              'again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final date = _date;
    return Form(
      key: _form,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is the end point of your goal. Coach reads it to check '
              'your progress and never changes it for you.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.md),
            TracendSegmentedControl<_Kind>(
              segments: const [
                (_Kind.weight, 'Weight'),
                (_Kind.bodyFat, 'Body fat'),
                (_Kind.physique, 'Look'),
              ],
              selected: _kind,
              onChanged: (kind) => setState(() {
                _kind = kind;
                _problem = null;
              }),
            ),
            const SizedBox(height: TracendSpacing.md),
            ..._fields(),
            const SizedBox(height: TracendSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('goal-target-date'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      date == null
                          ? 'Add a target date (optional)'
                          : 'By ${date.day}/${date.month}/${date.year}',
                    ),
                  ),
                ),
                if (date != null)
                  TextButton(
                    onPressed: () => setState(() => _date = null),
                    child: const Text('Remove'),
                  ),
              ],
            ),
            if (_problem != null) ...[
              const SizedBox(height: TracendSpacing.xs),
              Text(
                _problem!,
                key: const ValueKey('goal-target-problem'),
                style: theme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: TracendSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('goal-target-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving' : 'Save target'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() => switch (_kind) {
    _Kind.weight => [
      TextFormField(
        key: const ValueKey('goal-target-weight'),
        controller: _weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Target weight',
          suffixText: 'kg',
          helperText: widget.minWeightKg == null
              ? null
              : 'Lowest healthy target for your height: '
                    '${widget.minWeightKg!.toStringAsFixed(1)} kg',
        ),
        validator: _weightError,
      ),
    ],
    _Kind.bodyFat => [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: const ValueKey('goal-target-fat-min'),
              controller: _fatMin,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'From',
                suffixText: '%',
              ),
              validator: (_) => _fatError(_fatMin),
            ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: TextFormField(
              key: const ValueKey('goal-target-fat-max'),
              controller: _fatMax,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'To',
                suffixText: '%',
              ),
              validator: (_) => _fatError(_fatMax),
            ),
          ),
        ],
      ),
    ],
    _Kind.physique => [
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          for (final entry in physiqueGoalLabels.entries)
            ChoiceChip(
              key: ValueKey('goal-physique-${entry.key}'),
              label: Text(entry.value),
              selected: _physique == entry.key,
              onSelected: (selected) => setState(() {
                _physique = selected ? entry.key : null;
                _problem = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: TracendSpacing.sm),
      TextFormField(
        key: const ValueKey('goal-target-note'),
        controller: _note,
        maxLength: goalPhysiqueNoteMaxLength,
        decoration: const InputDecoration(
          labelText: 'In your own words (optional)',
        ),
      ),
    ],
  };
}
