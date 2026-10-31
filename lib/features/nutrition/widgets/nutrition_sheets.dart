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
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';
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
            widget.candidates.any(
                  (candidate) =>
                      candidate.source == MealSource.label ||
                      candidate.source == MealSource.labelUnverified,
                )
                ? 'Values read from a label can still be misread. Compare the '
                      'name and the numbers with the pack, choose how much you '
                      'ate, then confirm only what you ate.'
                : 'These are estimates from your photo. Check portions, oil, '
                      'sauces, and hidden ingredients, then confirm only what '
                      'you ate.',
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

  /// The chosen portion and its size. Both clear when the athlete types a
  /// value, so the chooser never shows a portion the values are not.
  late PortionKind? _portion = widget.candidate.unit == null
      ? null
      : initialPortionKind(
          portionSize: widget.candidate.portionSize,
          servingSize: widget.candidate.servingSize,
          packSize: widget.candidate.packSize,
          unit: widget.candidate.unit!,
        );
  late double? _portionSize = _portion == null
      ? null
      : widget.candidate.portionSize;
  late final _amount = TextEditingController(
    text: amountText(widget.candidate.portionSize ?? 100),
  );
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
      _amount,
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
        portionSize: _portionSize,
      ),
    );
  }

  /// A value typed by hand is no longer a portion of the chooser.
  void _typed() {
    setState(() {
      _portion = null;
      _portionSize = null;
    });
    _notify();
  }

  /// The largest typed amount: the most one meal row's portion holds.
  static const _maxAmount = 5000.0;

  /// The values of [size] units, or null when one meal row cannot hold them.
  PortionNutrients? _storable(double size) {
    final values = widget.candidate.perUnit?.scale(size);
    return values != null && values.storable ? values : null;
  }

  String? _amountError(String? value) {
    final grams = parseDecimal(value);
    if (grams == null || grams <= 0 || grams > _maxAmount) {
      return 'Enter 1 to 5000 g';
    }
    return _storable(grams) == null
        ? 'That is more than one meal can hold'
        : null;
  }

  /// Recalculates every value from the stored per-unit values for a portion
  /// one meal row can hold, and only then selects it. The fields stay
  /// editable afterwards.
  void _applyPortion(PortionKind kind, double size) {
    final values = _storable(size);
    if (values == null) return;
    setState(() {
      _portion = kind;
      _portionSize = size;
    });
    _serving.text = portionLabel(kind, size, widget.candidate.unit!);
    _calories.text = _shown(values.calories);
    _protein.text = _shown(values.protein);
    _carbs.text = _shown(values.carbohydrate);
    _fat.text = _shown(values.fat);
    _notify();
  }

  void _choosePortion(PortionKind kind) {
    switch (kind) {
      case PortionKind.serving:
        _applyPortion(kind, widget.candidate.servingSize!);
      case PortionKind.pack:
        _applyPortion(kind, widget.candidate.packSize!);
      case PortionKind.amount:
        // Start from an amount that can be confirmed, never from a refused one.
        if (_amountError(_amount.text) != null) {
          _amount.text = amountText(
            _portionSize ?? widget.candidate.servingSize ?? 100,
          );
        }
        final typed = parseDecimal(_amount.text);
        if (typed != null) _applyPortion(kind, typed);
    }
  }

  /// A typed amount recalculates while it can be confirmed. While it cannot,
  /// its message shows and the sheet refuses to confirm.
  void _typedAmount(String value) {
    final grams = parseDecimal(value);
    if (grams != null && _amountError(value) == null) {
      _applyPortion(PortionKind.amount, grams);
    } else {
      setState(() {});
    }
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
        if (widget.candidate.source case final source?)
          Align(
            alignment: Alignment.centerLeft,
            child: MealSourceBadge(source: source),
          ),
        if (widget.candidate.labelIssues.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xs),
          LabelIssuesNote(issues: widget.candidate.labelIssues),
        ],
        if (widget.selected && _offersPortions) ...[
          const SizedBox(height: TracendSpacing.sm),
          _portionChooser(context),
        ],
        if (widget.candidate.assumptions.isNotEmpty ||
            widget.candidate.question.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xs),
          MealModelNotes(
            assumptions: widget.candidate.assumptions,
            question: widget.candidate.question,
          ),
        ],
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

  /// Whether the chooser has anything to offer: a printed serving or pack,
  /// or (by weight) a typed amount. Millilitres never become grams.
  bool get _offersPortions {
    final unit = widget.candidate.unit;
    if (widget.candidate.perUnit == null || unit == null) return false;
    return unit == QuantityUnit.grams ||
        portionOptions(
          servingSize: widget.candidate.servingSize,
          packSize: widget.candidate.packSize,
          unit: unit,
        ).isNotEmpty;
  }

  Widget _portionChooser(BuildContext context) {
    final unit = widget.candidate.unit!;
    final options = portionOptions(
      servingSize: widget.candidate.servingSize,
      packSize: widget.candidate.packSize,
      unit: unit,
    );
    final tooLarge = [
      for (final option in options)
        if (_storable(option.size) == null) option,
    ];
    final errorStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.tracendColors.stateDanger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How much did you eat?',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: TracendSpacing.xs),
        TracendSegmentedControl<PortionKind>(
          segments: [
            for (final option in options)
              (
                option.kind,
                option.kind == PortionKind.serving ? '1 serving' : 'Whole pack',
              ),
            if (unit == QuantityUnit.grams) (PortionKind.amount, 'Grams'),
          ],
          selected: _portion,
          disabled: {for (final option in tooLarge) option.kind},
          onChanged: _choosePortion,
        ),
        for (final option in tooLarge)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.xxs),
            child: Text(
              '${option.label} is more than one meal can hold. Log part of '
              'it instead.',
              style: errorStyle,
            ),
          ),
        if (_portion == PortionKind.amount) ...[
          const SizedBox(height: TracendSpacing.xs),
          TextFormField(
            key: const ValueKey('portion-amount'),
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Grams eaten'),
            keyboardType: decimalKeyboard,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _amountError,
            onTapOutside: dismissKeyboard,
            onChanged: _typedAmount,
          ),
        ],
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: decimalKeyboard,
        validator: widget.selected ? _number : null,
        onTapOutside: dismissKeyboard,
        onChanged: (_) => _typed(),
      );
}

/// "From label", "Label unclear" or "Estimated": where a candidate's values
/// came from, as the server worked it out.
class MealSourceBadge extends StatelessWidget {
  const MealSourceBadge({required this.source, super.key});

  final MealSource source;

  static String label(MealSource source) => switch (source) {
    MealSource.label => 'From label',
    MealSource.labelUnverified => 'Label unclear',
    MealSource.estimate => 'Estimated',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final (background, foreground) = switch (source) {
      MealSource.label => (colors.accentSignalTint, colors.accentSignalInk),
      MealSource.labelUnverified => (
        colors.surfaceRaised,
        colors.stateAttention,
      ),
      MealSource.estimate => (colors.surfaceRaised, colors.textSecondary),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.xs,
          vertical: TracendSpacing.xxs,
        ),
        child: Text(
          label(source),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// Why a label's numbers were not trusted, one line per failed check.
class LabelIssuesNote extends StatelessWidget {
  const LabelIssuesNote({required this.issues, super.key});

  final List<String> issues;

  static String message(String issue) => switch (issue) {
    'energy_mismatch' =>
      "The calories don't match the protein, carbs and fat on the label.",
    'basis_mismatch' => "The per-serving and per-100 g columns don't agree.",
    'pack_mismatch' =>
      "Servings times serving size doesn't match the pack weight.",
    'energy_not_printed' =>
      'No calories were read, so they were calculated from protein, carbs '
          'and fat.',
    'serving_size_missing' =>
      'No serving weight was read, so other portions cannot be calculated.',
    'values_implausible' => 'Some values read from the label look impossible.',
    'volume_basis' =>
      'The label gives values per ml, so only its printed serving and pack '
          'can be chosen, and they were not checked against a weight.',
    'values_not_printed' =>
      'No nutrition values could be read, so these are estimates.',
    _ => 'Something on the label could not be checked.',
  };

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: context.tracendColors.stateAttention,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Check these numbers against the pack:', style: style),
        for (final issue in issues) Text('• ${message(issue)}', style: style),
      ],
    );
  }
}

/// What the model assumed and what it asks, shown as it wrote them.
class MealModelNotes extends StatelessWidget {
  const MealModelNotes({
    required this.assumptions,
    required this.question,
    super.key,
  });

  final List<String> assumptions;
  final String question;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.tracendColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assumptions.isNotEmpty)
          Text('Assumed: ${assumptions.join('; ')}', style: style),
        if (question.isNotEmpty) Text('Question: $question', style: style),
      ],
    );
  }
}
