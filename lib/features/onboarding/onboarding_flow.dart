import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.repository,
    required this.onCompleted,
    super.key,
  });

  final OnboardingRepository repository;
  final VoidCallback onCompleted;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _sections = [
    'Eligibility',
    'Path',
    'Goal',
    'Context',
    'Review',
    'Proposal',
  ];
  static const _goals = <String, String>{
    'fat_loss': 'Fat loss',
    'muscle_gain': 'Muscle gain',
    'recomposition': 'Recomposition',
    'strength': 'Strength',
    'aesthetic': 'Aesthetic emphasis',
  };

  final _equipment = TextEditingController(text: 'Full gym');
  final _nutrition = TextEditingController(text: 'No dietary restrictions');
  final _constraints = TextEditingController();
  final _currentPlan = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _adult = false;
  bool _needsClinicalSupport = false;
  bool _terms = false;
  bool _privacy = false;
  int _step = 0;
  String? _path;
  String _goal = 'recomposition';
  String _experience = 'beginner';
  int _trainingDays = 3;
  int _sessionMinutes = 60;
  double _weightKg = 75;
  OnboardingProposal? _proposal;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _equipment.dispose();
    _nutrition.dispose();
    _constraints.dispose();
    _currentPlan.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _payload => {
    'goal': _goal,
    'experience': _experience,
    'training_days': _trainingDays,
    'session_minutes': _sessionMinutes,
    'weight_kg': _weightKg.round(),
    'equipment': _equipment.text.trim(),
    'nutrition_context': _nutrition.text.trim(),
    'constraints': _constraints.text.trim(),
    if (_path == 'experienced') 'current_plan': _currentPlan.text.trim(),
  };

  Future<void> _restore() async {
    try {
      final draft = await widget.repository.loadDraft();
      if (draft != null) {
        final payload = draft.payload;
        _path = draft.path;
        _goal = payload['goal'] as String? ?? _goal;
        _experience = payload['experience'] as String? ?? _experience;
        _trainingDays = payload['training_days'] as int? ?? _trainingDays;
        _sessionMinutes = payload['session_minutes'] as int? ?? _sessionMinutes;
        _weightKg = (payload['weight_kg'] as num?)?.toDouble() ?? _weightKg;
        _equipment.text = payload['equipment'] as String? ?? _equipment.text;
        _nutrition.text =
            payload['nutrition_context'] as String? ?? _nutrition.text;
        _constraints.text = payload['constraints'] as String? ?? '';
        _currentPlan.text = payload['current_plan'] as String? ?? '';
        final restored = _sections.indexWhere(
          (section) => section.toLowerCase() == draft.currentSection,
        );
        if (restored > 0) _step = restored;
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      _error =
          'Your saved onboarding answers could not be restored. Retry before continuing.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continue() async {
    if (_saving) return;
    if (!_isStepValid()) {
      setState(() => _error = _validationMessage());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_step == 0) {
        await widget.repository.recordEligibilityAndConsent(
          eligible: true,
          experience: _experience,
          trainingDays: _trainingDays,
          sessionMinutes: _sessionMinutes,
        );
      }
      if (_step == 2) await widget.repository.saveGoal(_goal);
      if (_step < 4) {
        final next = _step + 1;
        await widget.repository.saveDraft(
          path: _path,
          currentSection: _sections[next].toLowerCase(),
          payload: _payload,
        );
        setState(() => _step = next);
      } else if (_step == 4) {
        await widget.repository.saveDraft(
          path: _path,
          currentSection: 'proposal',
          payload: _payload,
        );
        final proposal = await widget.repository.generateProposal();
        setState(() {
          _proposal = proposal;
          _step = 5;
        });
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      setState(() {
        _error =
            'This section could not be saved. Check the connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isStepValid() {
    if (_step == 0) {
      return _adult && !_needsClinicalSupport && _terms && _privacy;
    }
    if (_step == 1) return _path != null;
    if (_step == 3) {
      return _equipment.text.trim().isNotEmpty &&
          _nutrition.text.trim().isNotEmpty &&
          (_path != 'experienced' || _currentPlan.text.trim().isNotEmpty);
    }
    return true;
  }

  String _validationMessage() {
    if (_step == 0 && _needsClinicalSupport) {
      return 'Tracend cannot create a plan for clinical nutrition, pregnancy, acute injury, or rehabilitation needs.';
    }
    if (_step == 0) {
      return 'Confirm adult eligibility, terms, and privacy to continue.';
    }
    if (_step == 1) return 'Choose the onboarding path that fits you.';
    return 'Complete the required fields before continuing.';
  }

  Future<void> _respond(String action) async {
    final proposal = _proposal;
    if (proposal == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.respond(proposal.id, action);
      if (action == 'accept') {
        widget.onCompleted();
      } else {
        setState(() {
          _proposal = null;
          _step = 4;
          _error = action == 'reject'
              ? 'Proposal rejected. Your answers are unchanged.'
              : 'Revision requested. Review your answers before generating again.';
        });
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      setState(() {
        _error =
            'The proposal response was not saved. It has not changed your active plan.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up Tracend'),
        leading: _step > 0 && _step < 5
            ? IconButton(
                tooltip: 'Previous section',
                onPressed: _saving ? null : () => setState(() => _step--),
                icon: const Icon(CupertinoIcons.back),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TracendSpacing.gutter,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Section ${_step + 1} of ${_sections.length} · ${_sections[_step]}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  LinearProgressIndicator(
                    value: (_step + 1) / _sections.length,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TracendSpacing.gutter),
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
                ),
              ),
            ),
            if (_step < 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TracendSpacing.gutter,
                  TracendSpacing.sm,
                  TracendSpacing.gutter,
                  TracendSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: TracendSpacing.sm,
                          ),
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.tracendColors.stateDanger,
                                ),
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _continue,
                      child: _saving
                          ? const TracendLoadingIndicator(size: 20)
                          : Text(_step == 4 ? 'Build proposal' : 'Continue'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
    0 => _eligibility(),
    1 => _pathSelection(),
    2 => _goalSelection(),
    3 => _contextForm(),
    4 => _review(),
    _ => _proposalView(),
  };

  Widget _heading(String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: TracendSpacing.xs),
      Text(body, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: TracendSpacing.lg),
    ],
  );

  Widget _eligibility() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'First, confirm the boundary.',
        'Tracend supports healthy adults. It is not medical, pregnancy, rehabilitation, or eating-disorder care.',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _adult,
        onChanged: (value) => setState(() => _adult = value ?? false),
        title: const Text('I am 18 or older'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _needsClinicalSupport,
        onChanged: (value) => setState(() => _needsClinicalSupport = value),
        title: const Text(
          'I need clinical nutrition, pregnancy, acute injury, or rehabilitation support',
        ),
      ),
      const Divider(height: TracendSpacing.xl),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _terms,
        onChanged: (value) => setState(() => _terms = value ?? false),
        title: const Text('I accept the private-beta terms'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _privacy,
        onChanged: (value) => setState(() => _privacy = value ?? false),
        title: const Text('I have read the privacy notice'),
      ),
    ],
  );

  Widget _pathSelection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Choose your starting point.',
        'Both paths end with a proposal you must approve.',
      ),
      _ChoiceCard(
        selected: _path == 'beginner',
        icon: CupertinoIcons.compass_fill,
        title: 'Guide me',
        body:
            'Build a clear foundation from your schedule, equipment, and goal.',
        onTap: () => setState(() {
          _path = 'beginner';
          _experience = 'beginner';
        }),
      ),
      const SizedBox(height: TracendSpacing.sm),
      _ChoiceCard(
        selected: _path == 'experienced',
        icon: CupertinoIcons.chart_bar_alt_fill,
        title: 'Preserve what works',
        body:
            'Bring your current plan and keep confirmed practices where possible.',
        onTap: () => setState(() {
          _path = 'experienced';
          _experience = 'intermediate';
        }),
      ),
    ],
  );

  Widget _goalSelection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'What should the plan prioritize?',
        'Choose one primary direction for the first block.',
      ),
      RadioGroup<String>(
        groupValue: _goal,
        onChanged: (value) => setState(() => _goal = value ?? _goal),
        child: Column(
          children: _goals.entries
              .map(
                (entry) => RadioListTile<String>(
                  value: entry.key,
                  title: Text(entry.value),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );

  Widget _contextForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Make the proposal practical.',
        'These answers are autosaved when you continue.',
      ),
      Text(
        'Training days per week: $_trainingDays',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Slider(
        value: _trainingDays.toDouble(),
        min: 1,
        max: 7,
        divisions: 6,
        label: '$_trainingDays',
        onChanged: (value) => setState(() => _trainingDays = value.round()),
      ),
      Text(
        'Session duration: $_sessionMinutes minutes',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Slider(
        value: _sessionMinutes.toDouble(),
        min: 30,
        max: 120,
        divisions: 6,
        label: '$_sessionMinutes minutes',
        onChanged: (value) => setState(() => _sessionMinutes = value.round()),
      ),
      Text(
        'Current weight: ${_weightKg.round()} kg',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Slider(
        value: _weightKg,
        min: 40,
        max: 180,
        divisions: 140,
        label: '${_weightKg.round()} kg',
        onChanged: (value) => setState(() => _weightKg = value),
      ),
      const SizedBox(height: TracendSpacing.sm),
      _field(_equipment, 'Equipment', 'Example: full gym, dumbbells and bench'),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _nutrition,
        'Nutrition context',
        'Diet pattern, allergies, dislikes, meal schedule',
      ),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _constraints,
        'Constraints or preferences',
        'Optional exercise limitations or strong dislikes',
        required: false,
      ),
      if (_path == 'experienced') ...[
        const SizedBox(height: TracendSpacing.md),
        _field(
          _currentPlan,
          'Current plan and what works',
          'Describe your split, key lifts, targets, adherence, and plateau context',
        ),
      ],
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String helper, {
    bool required = true,
  }) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: 4,
    decoration: InputDecoration(
      labelText: required ? '$label *' : label,
      helperText: helper,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _review() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Review before generation.',
        'The mock provider receives only this confirmed snapshot.',
      ),
      TracendCard(
        child: Column(
          children: [
            _ReviewRow(
              'Path',
              _path == 'experienced' ? 'Preserve what works' : 'Guide me',
            ),
            const Divider(height: TracendSpacing.xl),
            _ReviewRow('Goal', _goals[_goal]!),
            const Divider(height: TracendSpacing.xl),
            _ReviewRow(
              'Schedule',
              '$_trainingDays days · $_sessionMinutes min',
            ),
            const Divider(height: TracendSpacing.xl),
            _ReviewRow(
              'Baseline',
              '${_weightKg.round()} kg · ${_equipment.text}',
            ),
            if (_path == 'experienced') ...[
              const Divider(height: TracendSpacing.xl),
              _ReviewRow('Keep', _currentPlan.text),
            ],
          ],
        ),
      ),
      const SizedBox(height: TracendSpacing.md),
      Text(
        'Generation creates a proposal only. Nothing becomes active until you approve it.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );

  Widget _proposalView() {
    final proposal = _proposal;
    if (proposal == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final structure = (proposal.training['weekly_structure'] as List).join(
      ' · ',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Your proposed starting plan.',
          'Review the tradeoffs before activating version 1.',
        ),
        StatusChip(
          label:
              '${proposal.confidence.toUpperCase()} confidence · approval required',
          icon: CupertinoIcons.doc_text_search,
        ),
        const SizedBox(height: TracendSpacing.md),
        TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                proposal.training['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: TracendSpacing.xs),
              Text('${proposal.training['block_weeks']} weeks · $structure'),
              const Divider(height: TracendSpacing.xl),
              Text(
                'Nutrition targets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${proposal.nutrition['calories']} kcal · ${proposal.nutrition['protein_g']}g protein · '
                '${proposal.nutrition['carbohydrate_g']}g carbs · ${proposal.nutrition['fat_g']}g fat',
              ),
            ],
          ),
        ),
        const SectionLabel('Why this proposal'),
        Text(proposal.rationale),
        const SectionLabel('Expected benefit'),
        Text(proposal.benefit),
        const SectionLabel('Downside and uncertainty'),
        Text(proposal.downside),
        if (_error != null) ...[
          const SizedBox(height: TracendSpacing.md),
          Semantics(liveRegion: true, child: Text(_error!)),
        ],
        const SizedBox(height: TracendSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : () => _respond('accept'),
            child: const Text('Approve plan'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _saving ? null : () => _respond('request_revision'),
            child: const Text('Request revision'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _saving ? null : () => _respond('reject'),
            child: const Text('Reject proposal'),
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(TracendRadii.card),
        onTap: onTap,
        child: TracendCard(
          child: Row(
            children: [
              Icon(icon, color: context.tracendColors.actionPrimary),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(body, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: selected
                    ? context.tracendColors.actionPrimary
                    : context.tracendColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
