import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:uuid/uuid.dart';
import 'package:tracend/shared/diagnostics.dart';

/// What the manual meal sheet asks to save. [idempotencyKey] belongs to this
/// meal as entered: a save that is repeated unchanged repeats the key.
class ManualMealResult {
  const ManualMealResult(this.mealType, this.food, this.idempotencyKey);
  final String mealType;
  final ManualFoodInput food;
  final String idempotencyKey;

  /// Whether [other] is the same meal as entered, whatever its key.
  bool sameMeal(ManualMealResult other) =>
      mealType == other.mealType &&
      mapEquals(food.toJson(), other.food.toJson());
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

enum LogMealMethod { camera, library, manual, turnOffPhotoAi }

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
    this.photoAiGranted = false,
    super.key,
  });

  final String initialMealType;

  /// False on the fixture repository, which offers manual entry only.
  final bool photosAvailable;

  /// The athlete granted the meal photo AI notice, so the sheet offers to
  /// turn it off.
  final bool photoAiGranted;

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
          ],
          TracendListRow(
            leading: const TracendRowIcon(icon: CupertinoIcons.pencil),
            title: 'Enter manually',
            subtitle: 'Type the food, serving, and nutrition.',
            onTap: () => _choose(LogMealMethod.manual),
          ),
        ],
      ),
      if (widget.photosAvailable && widget.photoAiGranted) ...[
        const SizedBox(height: TracendSpacing.sm),
        TextButton(
          onPressed: () => _choose(LogMealMethod.turnOffPhotoAi),
          child: const Text('Turn off meal photo AI'),
        ),
      ],
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

/// The keyboard for a nutrition value: iOS's plain number pad has no decimal
/// point, so 12.5 g could not be typed.
const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

/// A typed number, accepting a decimal comma; null when it is not one.
double? parseDecimal(String? text) =>
    double.tryParse((text ?? '').trim().replaceAll(',', '.'));

class ManualMealSheet extends StatefulWidget {
  const ManualMealSheet({
    required this.onSave,
    this.initialMealType = 'breakfast',
    super.key,
  });

  final String initialMealType;

  /// Saves the meal. The sheet stays open, with what was typed, until this
  /// completes; if it throws, the sheet says so and the athlete can try
  /// again.
  final Future<void> Function(ManualMealResult result) onSave;

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
  bool _saving = false;
  bool _failed = false;

  /// The save failed and the app could not tell whether it was written.
  bool _unknown = false;

  /// The last save that failed. The server may have written it before the
  /// reply was lost, so an unchanged retry repeats its key and adds nothing;
  /// a changed meal is a different save and gets a new key.
  ManualMealResult? _failedSave;

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
  String? _number(String? value) {
    final parsed = parseDecimal(value);
    return parsed == null || parsed < 0 ? 'Enter a valid number' : null;
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final entered = ManualMealResult(
      _mealType,
      ManualFoodInput(
        name: _name.text.trim(),
        servingLabel: _serving.text.trim(),
        calories: parseDecimal(_calories.text)!,
        protein: parseDecimal(_protein.text)!,
        carbohydrate: parseDecimal(_carbs.text)!,
        fat: parseDecimal(_fat.text)!,
      ),
      const Uuid().v4(),
    );
    final failed = _failedSave;
    final result = failed != null && failed.sameMeal(entered)
        ? failed
        : entered;
    setState(() {
      _saving = true;
      _failed = false;
      _unknown = false;
    });
    try {
      await widget.onSave(result);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      logNonCritical(e);
      if (!mounted) return;
      setState(() {
        _failedSave = result;
        _failed = true;
        _unknown = e is MealSaveOutcomeUnknown;
        _saving = false;
      });
    }
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
            keyboardType: decimalKeyboard,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _protein,
            decoration: const InputDecoration(labelText: 'Protein (g)'),
            keyboardType: decimalKeyboard,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _carbs,
            decoration: const InputDecoration(labelText: 'Carbohydrate (g)'),
            keyboardType: decimalKeyboard,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            controller: _fat,
            decoration: const InputDecoration(labelText: 'Fat (g)'),
            keyboardType: decimalKeyboard,
            validator: _number,
            onTapOutside: dismissKeyboard,
          ),
          const SizedBox(height: TracendSpacing.lg),
          if (_failed) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _unknown
                    ? 'The meal may not have been saved. What you entered is '
                          'kept; check the connection and confirm it again. '
                          'If it was saved, it is not added twice.'
                    : 'The meal was not saved. What you entered is kept; '
                          'check the connection and confirm it again.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.tracendColors.stateDanger,
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Saving…' : 'Confirm meal'),
          ),
        ],
      ),
    ),
  );
}

class CandidateSheet extends StatefulWidget {
  const CandidateSheet({
    required this.candidates,
    required this.onDiscard,
    this.canDiscard = true,
    super.key,
  });
  final List<MealCandidate> candidates;

  /// Whether the draft's analysis is over. A draft younger than the analysis
  /// can take may still get estimates, so it is not offered for deletion.
  final bool canDiscard;

  /// Deletes the draft meal. Shown as the way out when the draft has no
  /// estimates to review (its photo analysis failed).
  final Future<void> Function() onDiscard;
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
  bool _discarding = false;
  bool _discardFailed = false;

  Future<void> _discard() async {
    setState(() {
      _discarding = true;
      _discardFailed = false;
    });
    try {
      await widget.onDiscard();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      logNonCritical(e);
      if (mounted) {
        setState(() {
          _discarding = false;
          _discardFailed = true;
        });
      }
    }
  }

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
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) return _empty(context);
    return _review(context);
  }

  /// A draft with no estimates cannot be confirmed: say so and offer the way
  /// out instead of a Confirm button that never enables.
  Widget _empty(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.canDiscard
            ? 'Nothing to review. The photo could not be analyzed, so this '
                  'draft has no foods to confirm. Delete it, then log the '
                  'meal again or enter it manually. Nothing was added to '
                  'your totals.'
            : 'Nothing to review yet. This photo is still being analyzed, or '
                  'the analysis failed. Check again in a few minutes. '
                  'Nothing was added to your totals.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (_discardFailed) ...[
        const SizedBox(height: TracendSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            'The draft was not deleted. Check the connection and try again.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.tracendColors.stateDanger,
            ),
          ),
        ),
      ],
      if (widget.canDiscard) ...[
        const SizedBox(height: TracendSpacing.md),
        FilledButton(
          onPressed: _discarding ? null : _discard,
          child: Text(_discarding ? 'Deleting…' : 'Delete draft'),
        ),
      ],
    ],
  );

  Widget _review(BuildContext context) => Form(
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
    text: _shown(widget.candidate.calories),
  );
  late final _protein = TextEditingController(
    text: _shown(widget.candidate.protein),
  );
  late final _carbs = TextEditingController(
    text: _shown(widget.candidate.carbohydrate),
  );
  late final _fat = TextEditingController(text: _shown(widget.candidate.fat));
  bool _expanded = false;

  /// A value as the field shows it: whole, or to one decimal.
  static String _shown(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    // What is confirmed is what the fields show, rounded values included.
    _notify();
  }

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
    final parsed = parseDecimal(value);
    return parsed == null || parsed < 0 ? 'Enter zero or more' : null;
  }

  /// Whether every field holds a value that can be confirmed.
  bool get _valid =>
      _required(_name.text) == null &&
      _required(_serving.text) == null &&
      [
        _calories,
        _protein,
        _carbs,
        _fat,
      ].every((controller) => _number(controller.text) == null);

  void _notify() {
    final values = [
      _calories,
      _protein,
      _carbs,
      _fat,
    ].map((controller) => parseDecimal(controller.text)).toList();
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

  /// Closing the editor hides its fields, and hidden fields are not checked
  /// when the sheet confirms; so a value that cannot be confirmed keeps the
  /// editor open, with its message.
  void _toggleEditing() {
    if (_expanded && !_valid) {
      Form.of(context).validate();
      return;
    }
    setState(() => _expanded = !_expanded);
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
            onPressed: widget.selected ? _toggleEditing : null,
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
        keyboardType: decimalKeyboard,
        validator: widget.selected ? _number : null,
        onTapOutside: dismissKeyboard,
        onChanged: (_) {
          _notify();
          setState(() {});
        },
      );
}
