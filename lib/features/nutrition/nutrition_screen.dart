import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({
    this.repository = const FixtureNutritionRepository(),
    super.key,
  });

  final NutritionRepository repository;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _working = false;
  String? _error;
  NutritionTargets? _targets;
  NutritionSummary? _summary;
  List<MealEntry> _meals = const [];
  NutritionSchedule? _schedule;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.repository.loadTargets(),
        widget.repository.loadSummary(_date),
        widget.repository.loadMeals(_date),
        if (widget.repository is NutritionScheduleRepository)
          (widget.repository as NutritionScheduleRepository).loadSchedule(_date)
        else
          Future.value(
            const NutritionSchedule(title: 'Meal schedule', items: []),
          ),
      ]);
      if (!mounted) return;
      setState(() {
        _targets = values[0] as NutritionTargets?;
        _summary = values[1] as NutritionSummary;
        _meals = values[2] as List<MealEntry>;
        _schedule = values[3] as NutritionSchedule;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error = 'Nutrition data is unavailable. Pull to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeDate(int days) async {
    final today = DateTime.now();
    final candidate = DateTime(_date.year, _date.month, _date.day + days);
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (candidate.isAfter(todayOnly)) return;
    setState(() => _date = candidate);
    await _refresh();
  }

  bool get _isToday {
    final today = DateTime.now();
    return _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
  }

  String get _dateLabel => _isToday
      ? 'Today'
      : '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';

  Future<void> _openManualMeal([ScheduledMeal? scheduled]) async {
    final input = await showModalBottomSheet<_ManualMealResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ManualMealSheet(),
    );
    if (input == null) return;
    await _run(() {
      final repository = widget.repository;
      if (scheduled != null && repository is ScheduledMealLogger) {
        return (repository as ScheduledMealLogger).saveScheduledMeal(
          date: _date,
          scheduleItemId: scheduled.id,
          mealType: input.mealType,
          food: input.food,
        );
      }
      return repository.saveManualMeal(
        date: _date,
        mealType: input.mealType,
        food: input.food,
      );
    });
  }

  Future<void> _reviewFixture() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final mealId = await widget.repository.createFixtureMeal(
        date: _date,
        mealType: 'lunch',
      );
      await _openCandidateReview(mealId);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Meal analysis is unavailable. Enter the meal manually instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _selectMealPhoto(ImageSource source) async {
    final repository = widget.repository;
    if (repository is! MealPhotoRepository) return;
    final photo = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
      requestFullMetadata: false,
    );
    if (photo == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final mealId = await (repository as MealPhotoRepository).analyzeMealPhoto(
        date: _date,
        mealType: 'lunch',
        bytes: await photo.readAsBytes(),
      );
      await _openCandidateReview(mealId);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Meal photo analysis is unavailable. Enter the meal manually; no estimate was added to totals.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openCandidateReview(String mealId) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final candidates = await widget.repository.loadCandidates(mealId);
      if (!mounted) return;
      setState(() => _working = false);
      final selected = await showModalBottomSheet<List<MealCandidate>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _CandidateSheet(candidates: candidates),
      );
      if (selected == null || selected.isEmpty) return;
      await _run(() => widget.repository.confirmCandidates(mealId, selected));
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Draft could not be opened. Retry or delete it and enter the meal manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String failureMessage =
        'Meal was not saved. Your confirmed totals are unchanged.',
  }) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() => _error = failureMessage);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteMeal(MealEntry meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this meal?'),
        content: const Text(
          'The meal and its nutrition values will be removed from today’s totals. This action is recorded for account security.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete meal'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.repository.deleteMeal(meal.id),
      failureMessage:
          'Meal was not deleted. Your confirmed totals are unchanged.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final targets = _targets;
    final colors = context.tracendColors;
    final nextMeal = _schedule?.nextMeal;
    return TracendScrollView(
      title: 'Nutrition',
      subtitle: 'Confirmed meals only · $_dateLabel',
      children: [
        Row(
          children: [
            IconButton.outlined(
              key: const ValueKey('nutrition-previous-day'),
              tooltip: 'Previous day',
              onPressed: _loading ? null : () => _changeDate(-1),
              icon: const Icon(CupertinoIcons.chevron_left),
            ),
            Expanded(
              child: Text(
                _isToday ? 'Today’s log' : 'Saved daily log · $_dateLabel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.outlined(
              key: const ValueKey('nutrition-next-day'),
              tooltip: 'Next day',
              onPressed: _loading || _isToday ? null : () => _changeDate(1),
              icon: const Icon(CupertinoIcons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.md),
        if (_loading) const LinearProgressIndicator(minHeight: 3),
        if (_error != null) ...[
          TracendCard(
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: colors.stateAttention,
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.md),
        ],
        if (nextMeal != null) ...[
          TracendCard(
            radius: TracendRadii.decision,
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TracendPill(
                  label:
                      '${nextMeal.status == 'due' ? 'Due now' : 'Next meal'} · ${nextMeal.time}',
                  icon: CupertinoIcons.clock_fill,
                  color: nextMeal.status == 'due'
                      ? colors.stateAttention
                      : colors.actionPrimary,
                ),
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  nextMeal.label,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: TracendSpacing.xs),
                for (final food in nextMeal.foods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TracendSpacing.xxs),
                    child: Text('${food['name']} · ${food['quantity']}'),
                  ),
                const SizedBox(height: TracendSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _openManualMeal(nextMeal),
                    icon: const Icon(CupertinoIcons.check_mark_circled_solid),
                    label: const Text('Log meal'),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Confirmed nutrition'),
        ],
        TracendCard(
          radius: TracendRadii.decision,
          raised: nextMeal == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TracendPill(
                label: 'Deterministic totals',
                icon: CupertinoIcons.check_mark_circled_solid,
              ),
              const SizedBox(height: TracendSpacing.sm),
              Text(
                '${_number(summary?.calories)} kcal',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              Text(
                targets == null
                    ? '${summary?.confirmedMeals ?? 0} confirmed meals on $_dateLabel'
                    : 'of ${_number(targets.calories)} kcal · ${summary?.confirmedMeals ?? 0} confirmed meals',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: TracendSpacing.md),
              LinearProgressIndicator(
                value: _ratio(summary?.calories, targets?.calories),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: colors.actionPrimary,
                backgroundColor: colors.borderSubtle,
              ),
              const SizedBox(height: TracendSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _Macro(
                      label: 'Protein',
                      value:
                          '${_number(summary?.protein)} / ${_number(targets?.protein)}g',
                    ),
                  ),
                  Expanded(
                    child: _Macro(
                      label: 'Carbs',
                      value:
                          '${_number(summary?.carbohydrate)} / ${_number(targets?.carbohydrate)}g',
                    ),
                  ),
                  Expanded(
                    child: _Macro(
                      label: 'Fat',
                      value:
                          '${_number(summary?.fat)} / ${_number(targets?.fat)}g',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_schedule != null && _schedule!.items.isNotEmpty) ...[
          const SectionLabel('Meal schedule'),
          TracendCard(
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < _schedule!.items.length;
                  index++
                ) ...[
                  _ScheduledMealRow(item: _schedule!.items[index]),
                  if (index != _schedule!.items.length - 1)
                    const Divider(height: TracendSpacing.lg),
                ],
              ],
            ),
          ),
        ],
        const SectionLabel('Add a meal'),
        FilledButton.icon(
          onPressed: _working ? null : _openManualMeal,
          icon: _working
              ? const TracendLoadingIndicator(size: 18)
              : const Icon(CupertinoIcons.pencil),
          label: const Text('Enter manually'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : widget.repository is MealPhotoRepository
              ? () => _selectMealPhoto(ImageSource.camera)
              : _reviewFixture,
          icon: const Icon(CupertinoIcons.camera_viewfinder),
          label: Text(
            widget.repository is MealPhotoRepository
                ? 'Analyze meal photo'
                : 'Review sample analysis',
          ),
        ),
        if (widget.repository is MealPhotoRepository) ...[
          const SizedBox(height: TracendSpacing.sm),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => _selectMealPhoto(ImageSource.gallery),
            icon: const Icon(CupertinoIcons.photo_on_rectangle),
            label: const Text('Choose from Photo Library'),
          ),
        ],
        const SizedBox(height: TracendSpacing.xs),
        Text(
          widget.repository is MealPhotoRepository
              ? 'AI candidates are estimates. Review portions, oil, sauces and hidden ingredients before confirmation.'
              : 'Sample analysis is a local fixture. Nothing affects totals until you confirm it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SectionLabel(_isToday ? 'Today’s timeline' : '$_dateLabel timeline'),
        if (!_loading && _meals.isEmpty)
          const TracendCard(
            child: Text(
              'No confirmed meals yet. Manual logging stays available when analysis is unavailable.',
            ),
          )
        else
          for (final meal in _meals) ...[
            _MealCard(
              meal: meal,
              onReview: meal.status == 'draft' && !_working
                  ? () => _openCandidateReview(meal.id)
                  : null,
              onDelete: _working ? null : () => _deleteMeal(meal),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
      ],
    );
  }

  static String _number(num? value) =>
      value == null ? '—' : value.round().toString();
  static double _ratio(num? value, num? target) => target == null || target <= 0
      ? 0
      : (value! / target).clamp(0, 1).toDouble();
}

class _ScheduledMealRow extends StatelessWidget {
  const _ScheduledMealRow({required this.item});
  final ScheduledMeal item;
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final complete = item.status == 'logged';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: complete
                ? colors.stateStable.withValues(alpha: 0.16)
                : colors.surfaceRaised,
          ),
          child: Icon(
            complete ? CupertinoIcons.check_mark : CupertinoIcons.clock,
            size: 18,
            color: complete ? colors.stateStable : colors.textSecondary,
          ),
        ),
        const SizedBox(width: TracendSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    item.time,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                item.foods.map((food) => food['name']).join(' · '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                item.optional ? 'Optional · ${item.status}' : item.status,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManualMealResult {
  const _ManualMealResult(this.mealType, this.food);
  final String mealType;
  final ManualFoodInput food;
}

class _ManualMealSheet extends StatefulWidget {
  const _ManualMealSheet();
  @override
  State<_ManualMealSheet> createState() => _ManualMealSheetState();
}

class _ManualMealSheetState extends State<_ManualMealSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _serving = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  String _mealType = 'breakfast';

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
      _ManualMealResult(
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      TracendSpacing.gutter,
      TracendSpacing.lg,
      TracendSpacing.gutter,
      MediaQuery.viewInsetsOf(context).bottom + TracendSpacing.lg,
    ),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enter meal',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const _HideKeyboardButton(),
              ],
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Confirmed entries immediately contribute to today’s totals.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: 'Meal type'),
              items: const ['breakfast', 'lunch', 'dinner', 'snack']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _mealType = value!),
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Food name'),
              validator: _required,
              onTapOutside: _dismissKeyboard,
            ),
            TextFormField(
              controller: _serving,
              decoration: const InputDecoration(labelText: 'Serving'),
              validator: _required,
              onTapOutside: _dismissKeyboard,
            ),
            TextFormField(
              controller: _calories,
              decoration: const InputDecoration(labelText: 'Calories'),
              keyboardType: TextInputType.number,
              validator: _number,
              onTapOutside: _dismissKeyboard,
            ),
            TextFormField(
              controller: _protein,
              decoration: const InputDecoration(labelText: 'Protein (g)'),
              keyboardType: TextInputType.number,
              validator: _number,
              onTapOutside: _dismissKeyboard,
            ),
            TextFormField(
              controller: _carbs,
              decoration: const InputDecoration(labelText: 'Carbohydrate (g)'),
              keyboardType: TextInputType.number,
              validator: _number,
              onTapOutside: _dismissKeyboard,
            ),
            TextFormField(
              controller: _fat,
              decoration: const InputDecoration(labelText: 'Fat (g)'),
              keyboardType: TextInputType.number,
              validator: _number,
              onTapOutside: _dismissKeyboard,
            ),
            const SizedBox(height: TracendSpacing.lg),
            FilledButton(onPressed: _submit, child: const Text('Confirm meal')),
          ],
        ),
      ),
    ),
  );
}

class _CandidateSheet extends StatefulWidget {
  const _CandidateSheet({required this.candidates});
  final List<MealCandidate> candidates;
  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(TracendSpacing.gutter),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Review candidates',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const _HideKeyboardButton(),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              const Text(
                'Estimates can be wrong. Select recognized foods and correct names, servings, or nutrition before confirming.',
              ),
              const SizedBox(height: TracendSpacing.md),
              for (final item in widget.candidates) ...[
                _CandidateEditor(
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
                const SizedBox(height: TracendSpacing.sm),
              ],
              const SizedBox(height: TracendSpacing.md),
              FilledButton(
                onPressed: _selected.isEmpty ? null : _submit,
                child: const Text('Confirm selected foods'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CandidateEditor extends StatefulWidget {
  const _CandidateEditor({
    required this.candidate,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
  });
  final MealCandidate candidate;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final ValueChanged<MealCandidate> onChanged;

  @override
  State<_CandidateEditor> createState() => _CandidateEditorState();
}

class _CandidateEditorState extends State<_CandidateEditor> {
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
            '${_serving.text} · ${_calories.text} kcal · ${widget.candidate.confidence} confidence',
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
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Food name'),
            validator: widget.selected ? _required : null,
            onTapOutside: _dismissKeyboard,
            onChanged: (_) {
              _notify();
              setState(() {});
            },
          ),
          TextFormField(
            controller: _serving,
            decoration: const InputDecoration(labelText: 'Serving'),
            validator: widget.selected ? _required : null,
            onTapOutside: _dismissKeyboard,
            onChanged: (_) {
              _notify();
              setState(() {});
            },
          ),
          Row(
            children: [
              Expanded(child: _numberField(_calories, 'Calories')),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(child: _numberField(_protein, 'Protein (g)')),
            ],
          ),
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
        onTapOutside: _dismissKeyboard,
        onChanged: (_) {
          _notify();
          setState(() {});
        },
      );
}

void _dismissKeyboard(PointerDownEvent _) {
  FocusManager.instance.primaryFocus?.unfocus();
}

class _HideKeyboardButton extends StatelessWidget {
  const _HideKeyboardButton();

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

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: TracendSpacing.xxs),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.onReview,
    required this.onDelete,
  });
  final MealEntry meal;
  final VoidCallback? onReview;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              meal.status == 'confirmed'
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.clock,
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Text(
                meal.type,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(meal.status),
            IconButton(
              key: ValueKey('delete-meal-${meal.id}'),
              onPressed: onDelete,
              tooltip: 'Delete meal',
              icon: const Icon(CupertinoIcons.delete),
            ),
          ],
        ),
        if (meal.status == 'draft') ...[
          const SizedBox(height: TracendSpacing.xs),
          OutlinedButton.icon(
            key: ValueKey('review-meal-${meal.id}'),
            onPressed: onReview,
            icon: const Icon(CupertinoIcons.pencil),
            label: const Text('Review & edit draft'),
          ),
        ],
      ],
    ),
  );
}
