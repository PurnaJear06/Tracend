import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class ManualMealResult {
  const ManualMealResult(this.mealType, this.food);
  final String mealType;
  final ManualFoodInput food;
}

void dismissKeyboard(PointerDownEvent _) {
  FocusManager.instance.primaryFocus?.unfocus();
}

class HideKeyboardButton extends StatelessWidget {
  const HideKeyboardButton({super.key});

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: keyboardVisible
          ? TextButton.icon(
              key: const ValueKey('hide-keyboard'),
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              icon: const Icon(CupertinoIcons.keyboard_chevron_compact_down),
              label: const Text('Hide keyboard'),
            )
          : const SizedBox.shrink(),
    );
  }
}

const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

/// The meal type a new log most likely is, from the time it is logged.
String defaultMealType(DateTime now) {
  final minutes = now.hour * 60 + now.minute;
  if (minutes < 10 * 60 + 30) return 'breakfast';
  if (minutes < 15 * 60) return 'lunch';
  if (minutes < 17 * 60 + 30) return 'snack';
  return 'dinner';
}

enum LogMealMethod { camera, library, manual, sample }

class LogMealChoice {
  const LogMealChoice(this.mealType, this.method);
  final String mealType;
  final LogMealMethod method;
}

/// One entry point for every way to log a meal, shown in a sheet titled
/// "Log a meal". The meal type is chosen first so a photo meal is saved
/// under the right meal.
class LogMealSheet extends StatefulWidget {
  const LogMealSheet({
    required this.initialMealType,
    required this.photosAvailable,
    super.key,
  });

  final String initialMealType;

  /// False on the fixture repository, which offers a sample analysis
  /// instead of the camera.
  final bool photosAvailable;

  @override
  State<LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends State<LogMealSheet> {
  late String _mealType = widget.initialMealType;

  void _choose(LogMealMethod method) =>
      Navigator.pop(context, LogMealChoice(_mealType, method));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MealTypeChips(
        selected: _mealType,
        onSelected: (type) => setState(() => _mealType = type),
      ),
      const SizedBox(height: TracendSpacing.md),
      TracendGroupedList(
        children: [
          if (widget.photosAvailable) ...[
            TracendListRow(
              leading: const TracendRowIcon(icon: CupertinoIcons.camera_fill),
              title: 'Take a photo',
              subtitle: 'Tracend suggests the foods; you check them.',
              onTap: () => _choose(LogMealMethod.camera),
            ),
            TracendListRow(
              leading: const TracendRowIcon(
                icon: CupertinoIcons.photo_on_rectangle,
              ),
              title: 'Choose from Photo Library',
              subtitle: 'Use a photo you already took.',
              onTap: () => _choose(LogMealMethod.library),
            ),
          ] else
            TracendListRow(
              leading: const TracendRowIcon(
                icon: CupertinoIcons.camera_viewfinder,
              ),
              title: 'Review sample analysis',
              subtitle: 'A built-in example. Nothing counts until you confirm.',
              onTap: () => _choose(LogMealMethod.sample),
            ),
          TracendListRow(
            leading: const TracendRowIcon(icon: CupertinoIcons.pencil),
            title: 'Enter manually',
            subtitle: 'Type the food, serving, and nutrition.',
            onTap: () => _choose(LogMealMethod.manual),
          ),
        ],
      ),
    ],
  );
}

/// The four meal types as one row of choice chips, labeled "Meal" for
/// VoiceOver.
class MealTypeChips extends StatelessWidget {
  const MealTypeChips({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Meal',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.tracendColors.textSecondary,
        ),
      ),
      const SizedBox(height: TracendSpacing.xs),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          for (final type in mealTypes)
            ChoiceChip(
              label: Text(mealTypeLabel(type)),
              selected: selected == type,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) {
                if (type != selected) TracendHaptics.selection();
                onSelected(type);
              },
            ),
        ],
      ),
    ],
  );
}

class ManualMealSheet extends StatefulWidget {
  const ManualMealSheet({this.initialMealType = 'breakfast', super.key});

  final String initialMealType;

  @override
  State<ManualMealSheet> createState() => _ManualMealSheetState();
}

class _ManualMealSheetState extends State<ManualMealSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _serving = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  late String _mealType = widget.initialMealType;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _serving,
      _calories,
      _protein,
      _carbs,
      _fat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  String? _number(String? value) =>
      double.tryParse(value ?? '') == null ? 'Enter a valid number' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ManualMealResult(
        _mealType,
        ManualFoodInput(
          name: _name.text.trim(),
          servingLabel: _serving.text.trim(),
          calories: double.parse(_calories.text),
          protein: double.parse(_protein.text),
          carbohydrate: double.parse(_carbs.text),
          fat: double.parse(_fat.text),
        ),
      ),
    );
  }

  /// Shown in a sheet titled "Enter meal" with `scrollable: false`: the
  /// form brings its own scroll view so a drag dismisses the keyboard.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: HideKeyboardButton(),
          ),
          MealTypeChips(
            selected: _mealType,
            onSelected: (type) => setState(() => _mealType = type),
          ),
          const SizedBox(height: TracendSpacing.xs),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Food name'),
            validator: _required,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _serving,
            decoration: const InputDecoration(labelText: 'Serving'),
            validator: _required,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _calories,
            decoration: const InputDecoration(labelText: 'Calories'),
            keyboardType: TextInputType.number,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _protein,
            decoration: const InputDecoration(labelText: 'Protein (g)'),
            keyboardType: TextInputType.number,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _carbs,
            decoration: const InputDecoration(labelText: 'Carbohydrate (g)'),
            keyboardType: TextInputType.number,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _fat,
            decoration: const InputDecoration(labelText: 'Fat (g)'),
            keyboardType: TextInputType.number,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Confirm meal')),
        ],
      ),
    ),
  );
}

class CandidateSheet extends StatefulWidget {
  const CandidateSheet({required this.candidates, super.key});
  final List<MealCandidate> candidates;
  @override
  State<CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<CandidateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, MealCandidate> _edited = {
    for (final candidate in widget.candidates) candidate.id: candidate,
  };
  late final Set<String> _selected = widget.candidates
      .map((item) => item.id)
      .toSet();

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.candidates
          .where((candidate) => _selected.contains(candidate.id))
          .map((candidate) => _edited[candidate.id]!)
          .toList(),
    );
  }

  /// Shown in a sheet titled "Review candidates" with `scrollable: false`:
  /// the list brings its own scroll view so a drag dismisses the keyboard.
  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: HideKeyboardButton(),
          ),
          Text(
            'These are estimates from your photo. Check portions, oil, '
            'sauces, and hidden ingredients, then confirm only what you ate.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          for (final item in widget.candidates) ...[
            CandidateEditor(
              candidate: item,
              selected: _selected.contains(item.id),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _selected.add(item.id);
                } else {
                  _selected.remove(item.id);
                }
              }),
              onChanged: (candidate) => _edited[item.id] = candidate,
            ),
            const SizedBox(height: TracendSpacing.xs),
          ],
          const SizedBox(height: TracendSpacing.md),
          FilledButton(
            onPressed: _selected.isEmpty ? null : _submit,
            child: const Text('Confirm selected foods'),
          ),
        ],
      ),
    ),
  );
}

class CandidateEditor extends StatefulWidget {
  const CandidateEditor({
    required this.candidate,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    super.key,
  });
  final MealCandidate candidate;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final ValueChanged<MealCandidate> onChanged;

  @override
  State<CandidateEditor> createState() => _CandidateEditorState();
}

class _CandidateEditorState extends State<CandidateEditor> {
  late final _name = TextEditingController(text: widget.candidate.name);
  late final _serving = TextEditingController(
    text: widget.candidate.servingLabel,
  );
  late final _calories = TextEditingController(
    text: widget.candidate.calories.toStringAsFixed(0),
  );
  late final _protein = TextEditingController(
    text: widget.candidate.protein.toStringAsFixed(0),
  );
  late final _carbs = TextEditingController(
    text: widget.candidate.carbohydrate.toStringAsFixed(0),
  );
  late final _fat = TextEditingController(
    text: widget.candidate.fat.toStringAsFixed(0),
  );
  bool _expanded = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _serving,
      _calories,
      _protein,
      _carbs,
      _fat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter a value' : null;

  String? _number(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter zero or more' : null;
  }

  void _notify() {
    final values = [
      _calories,
      _protein,
      _carbs,
      _fat,
    ].map((controller) => double.tryParse(controller.text)).toList();
    if (values.any((value) => value == null)) return;
    widget.onChanged(
      widget.candidate.copyWith(
        name: _name.text.trim(),
        servingLabel: _serving.text.trim(),
        calories: values[0],
        protein: values[1],
        carbohydrate: values[2],
        fat: values[3],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TracendCard(
    child: Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: widget.selected,
          title: Text(_name.text),
          subtitle: Text(
            '${_serving.text} · ${_calories.text} kcal · '
            '${confidenceLabel(widget.candidate.confidence)}',
          ),
          onChanged: (value) => widget.onSelected(value ?? false),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.selected
                ? () => setState(() => _expanded = !_expanded)
                : null,
            icon: Icon(
              _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.pencil,
            ),
            label: Text(_expanded ? 'Done editing' : 'Edit estimate'),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Food name'),
            validator: widget.selected ? _required : null,
            onTapOutside: dismissKeyboard,
            onChanged: (_) {
              _notify();
              setState(() {});
            },
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _serving,
            decoration: const InputDecoration(labelText: 'Serving'),
            validator: widget.selected ? _required : null,
            onTapOutside: dismissKeyboard,
            onChanged: (_) {
              _notify();
              setState(() {});
            },
          ),
          const SizedBox(height: TracendSpacing.xs),
          Row(
            children: [
              Expanded(child: _numberField(_calories, 'Calories')),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(child: _numberField(_protein, 'Protein (g)')),
            ],
          ),
          const SizedBox(height: TracendSpacing.xs),
          Row(
            children: [
              Expanded(child: _numberField(_carbs, 'Carbs (g)')),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(child: _numberField(_fat, 'Fat (g)')),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _numberField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: widget.selected ? _number : null,
        onTapOutside: dismissKeyboard,
        onChanged: (_) {
          _notify();
          setState(() {});
        },
      );
}
