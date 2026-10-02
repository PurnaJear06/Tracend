import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/onboarding/health_activity.dart';
import 'package:tracend/features/onboarding/onboarding_proposal_view.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Weekday labels, ISO order (index 0 = Monday).
const onboardingWeekdayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.repository,
    required this.onCompleted,
    this.aiConsent,
    this.health,
    this.onSignOut,
    this.pollInterval = const Duration(seconds: 3),
    this.pollTimeout = const Duration(seconds: 150),
    this.currentYear,
    super.key,
  });

  final OnboardingRepository repository;
  final VoidCallback onCompleted;

  /// Records the AI coaching answer. Without one the step still asks, and the
  /// app asks again after onboarding.
  final AiCoachingConsentController? aiConsent;

  /// Apple Health, offered as an optional step; without one the step can only
  /// be skipped.
  final HealthRepository? health;
  final Future<void> Function()? onSignOut;
  final Duration pollInterval;

  /// Longer than the server's generation lease; after it the app offers a retry.
  final Duration pollTimeout;
  final int? currentYear;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _sections = [
    'Eligibility',
    'AI',
    'Path',
    'Goal',
    'Apple Health',
    'About you',
    'Schedule',
    'Equipment',
    'Food & limits',
    'Review',
    'Plan',
  ];
  static const _sectionKeys = [
    'eligibility',
    'ai',
    'path',
    'goal',
    'health',
    'about',
    'schedule',
    'equipment',
    'food',
    'review',
    'proposal',
  ];

  /// Sections saved by builds before 2026-10 map onto the new steps.
  static const _legacySections = {'context': _aboutStep};
  static const _eligibilityStep = 0;
  static const _aiStep = 1;
  static const _pathStep = 2;
  static const _goalStep = 3;
  static const _healthStep = 4;
  static const _aboutStep = 5;
  static const _scheduleStep = 6;
  static const _equipmentStep = 7;
  static const _foodStep = 8;
  static const _reviewStep = 9;
  static const _proposalStep = 10;

  static const _goals = <String, String>{
    'fat_loss': 'Fat loss',
    'muscle_gain': 'Muscle gain',
    'recomposition': 'Recomposition',
    'strength': 'Strength',
    'aesthetic': 'Aesthetic emphasis',
  };
  static const _sexes = <String, String>{
    'female': 'Female',
    'male': 'Male',
    'unspecified': 'Prefer not to say',
  };
  static const _activities = <String, (String, String)>{
    'mostly_sitting': ('Mostly sitting', 'Desk work, driving, studying'),
    'some_standing': (
      'On my feet some of the day',
      'Teaching, lab work, errands',
    ),
    'mostly_standing': (
      'On my feet most of the day',
      'Retail, nursing, hospitality',
    ),
    'physical_labour': ('Physical work', 'Construction, farming, warehouse'),
  };
  static const _equipmentChoices = <String, String>{
    'dumbbells': 'Dumbbells',
    'barbell': 'Barbell and rack',
    'bench': 'Bench',
    'cables': 'Cable machine',
    'machines': 'Weight machines',
    'pull_up_bar': 'Pull-up bar',
    'kettlebells': 'Kettlebells',
    'bands': 'Resistance bands',
  };

  /// Movement patterns the plan leaves out; the server enforces them.
  static const _avoidChoices = <String, String>{
    'squat': 'Squats',
    'lunge': 'Lunges and step-ups',
    'hinge': 'Deadlifts and hip hinges',
    'horizontal_push': 'Bench press and push-ups',
    'vertical_push': 'Overhead pressing',
    'horizontal_pull': 'Rows',
    'vertical_pull': 'Pull-ups and pulldowns',
  };
  static const _maxTrainingDays = 6;

  /// The server accepts weights from 35 to 250 kg.
  static const _minWeightKg = 35.0;
  static const _maxWeightKg = 250.0;
  static const _fieldLabels = {
    'sex': 'sex',
    'birth_year': 'birth year',
    'height_cm': 'height',
    'weight_kg': 'weight',
    'daily_activity': 'daily activity',
    'training_weekdays': 'training days',
    'session_minutes': 'session length',
    'equipment_items': 'equipment',
    'avoid_patterns': 'movements to avoid',
    'current_plan': 'current plan',
    'goal': 'goal',
    'path': 'starting point',
  };

  final _birthYear = TextEditingController();
  final _equipmentNote = TextEditingController();
  final _nutrition = TextEditingController(text: 'No dietary restrictions');
  final _constraints = TextEditingController();
  final _currentPlan = TextEditingController();
  final _revisionNote = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _adult = false;
  bool _needsClinicalSupport = false;
  bool _terms = false;
  bool _privacy = false;
  bool? _aiChoice;

  /// The answer already stored, so passing the step again adds no record.
  bool? _aiRecorded;
  int _step = _eligibilityStep;
  String? _path;
  String _goal = 'recomposition';
  String _experience = 'beginner';
  String? _sex;
  String? _dailyActivity;
  double _heightCm = 170;
  double _weightKg = 75;
  double? _targetWeightKg;
  Set<int> _weekdays = {1, 3, 5};
  int _sessionMinutes = 60;
  Set<String> _equipment = {};
  Set<String> _avoid = {};

  /// The movements-to-avoid question was answered (an empty set means none).
  /// Drafts from older builds have not answered it.
  bool _avoidAnswered = false;

  /// The Apple Health answer: `connected`, `skipped`, or `empty` (connected,
  /// but nothing came back). Older drafts have none; the step is optional.
  String? _healthImport;
  bool _healthBusy = false;
  String? _healthMessage;
  OnboardingHealthFacts? _healthFacts;

  /// The weight slider holds the Apple Health weight until the athlete moves it.
  bool _weightFromHealth = false;

  /// About you was answered, so Apple Health never overwrites it.
  bool _aboutPassed = false;

  HealthRepository get _health =>
      widget.health ?? const ManualHealthRepository();

  /// Plan step state: waiting for the server, or its generation failed.
  bool _generating = false;
  bool _generationFailed = false;

  /// The proposal expired (or was replaced) before it was answered.
  bool _proposalExpired = false;

  /// Bumped to stop a running poll (leaving the step, a new build).
  int _pollRun = 0;
  OnboardingProposal? _proposal;
  String? _error;

  int get _currentYear => widget.currentYear ?? DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _aiChoice = _aiRecorded = _answered(widget.aiConsent?.choice);
    _restore();
  }

  static bool? _answered(AiCoachingChoice? choice) => switch (choice) {
    AiCoachingChoice.granted => true,
    AiCoachingChoice.declined => false,
    _ => null,
  };

  @override
  void dispose() {
    _pollRun++;
    _birthYear.dispose();
    _equipmentNote.dispose();
    _nutrition.dispose();
    _constraints.dispose();
    _currentPlan.dispose();
    _revisionNote.dispose();
    super.dispose();
  }

  int? get _birthYearValue => int.tryParse(_birthYear.text.trim());

  static double _half(double kg) => (kg * 2).round() / 2;

  Map<String, dynamic> get _payload {
    final weekdays = _weekdays.toList()..sort();
    return {
      'goal': _goal,
      'experience': _experience,
      'sex': _sex,
      'birth_year': _birthYearValue,
      'height_cm': _heightCm.round(),
      'weight_kg': _half(_weightKg),
      'target_weight_kg': _targetWeightKg == null
          ? null
          : _half(_targetWeightKg!),
      'daily_activity': _dailyActivity,
      'training_weekdays': weekdays,
      // Read by builds before 2026-10 as a day count.
      'training_days': weekdays.length,
      'session_minutes': _sessionMinutes,
      'equipment_items': _equipment.toList()..sort(),
      'equipment': _equipmentNote.text.trim(),
      'nutrition_context': _nutrition.text.trim(),
      'constraints': _constraints.text.trim(),
      if (_avoidAnswered) 'avoid_patterns': _avoid.toList()..sort(),
      'health_import': ?_healthImport,
      if (_path == 'experienced') 'current_plan': _currentPlan.text.trim(),
      if (_revisionNote.text.trim().isNotEmpty)
        'revision_note': _revisionNote.text.trim(),
    };
  }

  /// An even spread for a day count saved by builds before 2026-10.
  static Set<int> _spreadFor(int days) => switch (days.clamp(1, 6)) {
    1 => {1},
    2 => {1, 4},
    3 => {1, 3, 5},
    4 => {1, 2, 4, 5},
    5 => {1, 2, 3, 5, 6},
    _ => {1, 2, 3, 4, 5, 6},
  };

  Future<void> _restore() async {
    var resumeGeneration = false;
    try {
      final draft = await widget.repository.loadDraft();
      if (draft != null) {
        final payload = draft.payload;
        _path = draft.path;
        _goal = payload['goal'] as String? ?? _goal;
        _experience = payload['experience'] as String? ?? _experience;
        _sex = payload['sex'] as String?;
        final birthYear = payload['birth_year'];
        if (birthYear is num) _birthYear.text = '${birthYear.toInt()}';
        _heightCm = (payload['height_cm'] as num?)?.toDouble() ?? _heightCm;
        _weightKg = (payload['weight_kg'] as num?)?.toDouble() ?? _weightKg;
        _targetWeightKg = (payload['target_weight_kg'] as num?)?.toDouble();
        _dailyActivity = payload['daily_activity'] as String?;
        final weekdays = payload['training_weekdays'];
        if (weekdays is List) {
          _weekdays = weekdays
              .whereType<num>()
              .map((day) => day.toInt())
              .where((day) => day >= 1 && day <= 7)
              .take(_maxTrainingDays)
              .toSet();
        } else if (payload['training_days'] is num) {
          _weekdays = _spreadFor((payload['training_days'] as num).toInt());
        }
        _sessionMinutes =
            (payload['session_minutes'] as num?)?.toInt() ?? _sessionMinutes;
        final equipment = payload['equipment_items'];
        if (equipment is List) {
          _equipment = equipment
              .whereType<String>()
              .where(_equipmentChoices.containsKey)
              .toSet();
        }
        _equipmentNote.text = payload['equipment'] as String? ?? '';
        _nutrition.text =
            payload['nutrition_context'] as String? ?? _nutrition.text;
        _constraints.text = payload['constraints'] as String? ?? '';
        final avoid = payload['avoid_patterns'];
        if (avoid is List) {
          _avoidAnswered = true;
          _avoid = avoid
              .whereType<String>()
              .where(_avoidChoices.containsKey)
              .toSet();
        }
        _currentPlan.text = payload['current_plan'] as String? ?? '';
        _revisionNote.text = payload['revision_note'] as String? ?? '';
        final healthImport = payload['health_import'];
        if (const ['connected', 'skipped', 'empty'].contains(healthImport)) {
          _healthImport = healthImport as String;
        }
        var restored = _sectionKeys.indexOf(draft.currentSection);
        if (restored < 0) {
          restored = _legacySections[draft.currentSection] ?? _eligibilityStep;
        }
        // A draft from an older build lacks the newer answers: continue from
        // the first step that asks for them.
        if (restored > _aboutStep && !payload.containsKey('sex')) {
          restored = _aboutStep;
        }
        if (restored > 0) _step = restored;
        _aboutPassed = _step > _aboutStep;
        resumeGeneration = _step == _proposalStep;
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      _error =
          'Your saved onboarding answers could not be restored. Retry before continuing.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (resumeGeneration && mounted) unawaited(_resumeGeneration());
    if (mounted && _healthImport != 'skipped') unawaited(_loadHealthFacts());
  }

  /// Reopened with Apple Health already connected (an earlier run, or a sync
  /// that finished before the app closed): show what it holds.
  Future<void> _loadHealthFacts() async {
    try {
      final status = await _health.loadStatus();
      if (status.state == HealthConnectionState.manualOnly ||
          status.state == HealthConnectionState.unavailable) {
        return;
      }
      final facts = onboardingHealthFacts(
        await _health.loadHistory(),
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _healthFacts = facts;
        _healthImport ??= facts.hasData ? 'connected' : 'empty';
        _prefillFromHealth(facts);
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }

  Future<void> _connectHealth() async {
    if (_healthBusy) return;
    setState(() {
      _healthBusy = true;
      _healthMessage = null;
      _error = null;
    });
    try {
      final status = await _health.connectAndSync();
      if (!mounted) return;
      if (status.state == HealthConnectionState.manualOnly ||
          status.state == HealthConnectionState.unavailable) {
        setState(() {
          _healthBusy = false;
          _healthMessage = status.accessError == null
              ? 'Apple Health is not available on this device. You can skip this step.'
              : status.detail;
        });
        return;
      }
      final facts = onboardingHealthFacts(
        await _health.loadHistory(),
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _healthBusy = false;
        _healthFacts = facts;
        _healthImport = facts.hasData ? 'connected' : 'empty';
        _prefillFromHealth(facts);
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      setState(() {
        _healthBusy = false;
        _healthMessage =
            'Apple Health could not be read. Check the connection and try again, or skip this step.';
      });
    }
  }

  /// The newest Apple Health weight starts the weight slider, until About you
  /// has been answered.
  void _prefillFromHealth(OnboardingHealthFacts facts) {
    final weight = facts.latestWeightKg;
    if (_aboutPassed || weight == null) return;
    _weightKg = weight.clamp(_minWeightKg, _maxWeightKg);
    _weightFromHealth = true;
  }

  Future<void> _skipHealth() async {
    setState(() {
      _healthImport = 'skipped';
      _healthMessage = null;
    });
    await _continue();
  }

  /// Reopened on the Plan step: show the stored proposal, keep waiting for a
  /// running generation, or go back to Review.
  Future<void> _resumeGeneration() async {
    setState(() {
      _generating = true;
      _generationFailed = false;
    });
    try {
      final generation = await widget.repository.loadGeneration();
      if (!mounted) return;
      if (generation != null && generation.proposalExpired) {
        _showProposalExpired();
        return;
      }
      if (generation == null ||
          generation.status == 'superseded' ||
          (generation.status == 'succeeded' && !generation.readyForReview)) {
        setState(() {
          _generating = false;
          _step = _reviewStep;
        });
        return;
      }
      await _follow(generation);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) _showGenerationFailure();
    }
  }

  void _showGenerationFailure() => setState(() {
    _generating = false;
    _generationFailed = true;
  });

  void _showProposalExpired() => setState(() {
    _proposal = null;
    _generating = false;
    _generationFailed = false;
    _proposalExpired = true;
    _error = null;
    _step = _proposalStep;
  });

  /// Polls the generation until it has a proposal, fails, or takes too long.
  Future<void> _follow(OnboardingGeneration first) async {
    final run = ++_pollRun;
    final deadline = DateTime.now().add(widget.pollTimeout);
    var generation = first;
    try {
      while (true) {
        if (!mounted || run != _pollRun) return;
        if (generation.proposalExpired) {
          _showProposalExpired();
          return;
        }
        if (generation.readyForReview) {
          final proposal = await widget.repository.loadProposal(
            generation.proposalId!,
          );
          if (!mounted || run != _pollRun) return;
          setState(() {
            _proposal = proposal;
            _generating = false;
            _generationFailed = false;
            _step = _proposalStep;
          });
          return;
        }
        if (!generation.running || DateTime.now().isAfter(deadline)) {
          _showGenerationFailure();
          return;
        }
        await Future<void>.delayed(widget.pollInterval);
        if (!mounted || run != _pollRun) return;
        generation = await widget.repository.loadGeneration() ?? generation;
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted && run == _pollRun) _showGenerationFailure();
    }
  }

  Future<void> _buildPlan() async {
    setState(() {
      _saving = true;
      _error = null;
      _proposal = null;
      _generationFailed = false;
      _proposalExpired = false;
    });
    try {
      await widget.repository.saveDraft(
        path: _path,
        currentSection: _sectionKeys[_proposalStep],
        payload: _payload,
      );
      final generation = await widget.repository.startGeneration();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _generating = true;
        _step = _proposalStep;
      });
      await _follow(generation);
    } on OnboardingAnswersIncomplete catch (error) {
      if (!mounted) return;
      final labels = error.missing.map((key) => _fieldLabels[key] ?? key);
      setState(() {
        _saving = false;
        _step = _stepForMissing(error.missing);
        _error =
            error.missing.length == 1 && error.missing.first == 'avoid_patterns'
            ? 'You wrote a limitation. Choose the movements your plan should leave out, or none, then build your plan.'
            : 'Add your ${labels.join(', ')} to build your plan.';
      });
    } on OnboardingPlanInfeasible catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = error.change.contains('avoid_patterns')
            ? _foodStep
            : _stepForMissing(error.change);
        _error = switch (_step) {
          _scheduleStep =>
            'Tracend could not fit a safe plan into these sessions. Choose longer sessions, then build again.',
          _aboutStep =>
            'Tracend could not set safe nutrition targets from these answers. Check your weight and daily activity, then build again.',
          _foodStep =>
            'With your equipment and the movements you avoid, some training days would have no exercise. Avoid fewer movements or add equipment, then build again.',
          _ =>
            'With this equipment, some training days would have no exercise. Add equipment, then build again.',
        };
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Your plan could not be started. Check the connection and try again.';
      });
    }
  }

  int _stepForMissing(List<String> missing) {
    if (missing.contains('path')) return _pathStep;
    if (missing.contains('goal')) return _goalStep;
    const about = ['sex', 'birth_year', 'height_cm', 'weight_kg'];
    if (missing.any(about.contains) || missing.contains('daily_activity')) {
      return _aboutStep;
    }
    if (missing.contains('training_weekdays') ||
        missing.contains('session_minutes')) {
      return _scheduleStep;
    }
    if (missing.contains('equipment_items')) return _equipmentStep;
    return _foodStep;
  }

  Future<void> _continue() async {
    if (_saving) return;
    if (!_isStepValid()) {
      setState(() => _error = _validationMessage());
      return;
    }
    if (_step == _reviewStep) {
      await _buildPlan();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_step == _eligibilityStep) {
        await widget.repository.recordEligibilityAndConsent(
          eligible: true,
          experience: _experience,
          trainingDays: _weekdays.length,
          sessionMinutes: _sessionMinutes,
        );
      }
      if (_step == _aiStep && _aiChoice != _aiRecorded) {
        await widget.aiConsent?.record(granted: _aiChoice!);
        _aiRecorded = _aiChoice;
      }
      if (_step == _goalStep) await widget.repository.saveGoal(_goal);
      if (_step == _foodStep) _avoidAnswered = true;
      if (_step == _aboutStep) _aboutPassed = true;
      final next = _step + 1;
      await widget.repository.saveDraft(
        path: _path,
        currentSection: _sectionKeys[next],
        payload: _payload,
      );
      setState(() => _step = next);
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

  bool _isStepValid() => switch (_step) {
    _eligibilityStep => _adult && !_needsClinicalSupport && _terms && _privacy,
    _aiStep => _aiChoice != null,
    _pathStep => _path != null,
    _healthStep => _healthImport != null && !_healthBusy,
    _aboutStep =>
      _sex != null && _dailyActivity != null && _birthYearError() == null,
    _scheduleStep => _weekdays.isNotEmpty,
    _foodStep =>
      _nutrition.text.trim().isNotEmpty &&
          (_path != 'experienced' || _currentPlan.text.trim().isNotEmpty),
    _ => true,
  };

  String? _birthYearError() {
    final year = _birthYearValue;
    if (year == null) return 'Enter your birth year.';
    final age = _currentYear - year;
    if (age < 18) return 'Tracend is for adults 18 and over.';
    if (age > 100) return 'Check the year.';
    return null;
  }

  String _validationMessage() {
    if (_step == _eligibilityStep && _needsClinicalSupport) {
      return 'Tracend cannot create a plan for clinical nutrition, pregnancy, acute injury, or rehabilitation needs.';
    }
    return switch (_step) {
      _eligibilityStep =>
        'Confirm adult eligibility, terms, and privacy to continue.',
      _aiStep => 'Choose whether to allow AI coaching.',
      _pathStep => 'Choose the onboarding path that fits you.',
      _healthStep => 'Connect Apple Health, or choose Skip for now.',
      _aboutStep =>
        _sex == null
            ? 'Choose an option for sex.'
            : _dailyActivity == null
            ? 'Choose how active you are outside training.'
            : _birthYearError()!,
      _scheduleStep => 'Choose at least one training day.',
      _ => 'Complete the required fields before continuing.',
    };
  }

  Future<void> _respond(String action, {String? note}) async {
    final proposal = _proposal;
    if (proposal == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.respond(proposal.id, action, note: note);
      if (action == 'accept') {
        widget.onCompleted();
        return;
      }
      _revisionNote.text = action == 'request_revision' ? (note ?? '') : '';
      await widget.repository.saveDraft(
        path: _path,
        currentSection: _sectionKeys[_reviewStep],
        payload: _payload,
      );
      setState(() {
        _proposal = null;
        _step = _reviewStep;
        _error = action == 'reject'
            ? 'Proposal rejected. Your answers are unchanged.'
            : 'Change your answers if needed, then build the plan again.';
      });
    } on OnboardingProposalStale {
      if (mounted) _showProposalExpired();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      setState(() {
        _error = 'Your response was not saved. Nothing has changed; try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestRevision() async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RevisionSheet(),
    );
    if (note == null) return;
    await _respond('request_revision', note: note.isEmpty ? null : note);
  }

  void _back() {
    _pollRun++;
    setState(() {
      _generating = false;
      _generationFailed = false;
      _proposalExpired = false;
      _error = null;
      _step = _step == _proposalStep ? _reviewStep : _step - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final onPlan = _step == _proposalStep;
    final canGoBack =
        _step > _eligibilityStep && (!onPlan || _proposal == null) && !_saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up Tracend'),
        leading: canGoBack
            ? IconButton(
                tooltip: 'Previous section',
                onPressed: _back,
                icon: const Icon(CupertinoIcons.back),
              )
            : null,
        actions: [
          if (widget.onSignOut != null)
            TextButton(
              onPressed: _saving ? null : () => widget.onSignOut!(),
              child: const Text('Sign out'),
            ),
        ],
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
                  child: KeyedSubtree(
                    key: ValueKey(
                      '$_step-${_proposal?.id}-$_generating-$_generationFailed-$_proposalExpired',
                    ),
                    child: _stepBody(),
                  ),
                ),
              ),
            ),
            if (!onPlan)
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
                    if (_error != null) _errorText(),
                    FilledButton(
                      onPressed: _saving ? null : _continue,
                      child: _saving
                          ? const TracendLoadingIndicator(size: 20)
                          : Text(
                              _step == _reviewStep
                                  ? 'Build my plan'
                                  : 'Continue',
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorText() => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
      child: Text(
        _error!,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.tracendColors.stateDanger,
        ),
      ),
    ),
  );

  Widget _stepBody() => switch (_step) {
    _eligibilityStep => _eligibility(),
    _aiStep => _aiCoaching(),
    _pathStep => _pathSelection(),
    _goalStep => _goalSelection(),
    _healthStep => _appleHealth(),
    _aboutStep => _aboutYou(),
    _scheduleStep => _schedule(),
    _equipmentStep => _equipmentSelection(),
    _foodStep => _foodAndLimits(),
    _reviewStep => _review(),
    _ => _plan(),
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

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(
      top: TracendSpacing.md,
      bottom: TracendSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
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

  Widget _aiCoaching() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Allow AI coaching?',
        'Your answer is saved when you continue. You can change it later in Account.',
      ),
      AiCoachingDisclosure(
        notice: widget.aiConsent?.notice ?? AiNotice.builtIn,
      ),
      const SizedBox(height: TracendSpacing.lg),
      _ChoiceCard(
        selected: _aiChoice == true,
        icon: CupertinoIcons.sparkles,
        title: 'Allow AI coaching',
        body:
            'An AI model drafts your starting plan within Tracend\'s safety ranges and writes the Coach chat and daily decision.',
        onTap: () => setState(() => _aiChoice = true),
      ),
      const SizedBox(height: TracendSpacing.sm),
      _ChoiceCard(
        selected: _aiChoice == false,
        icon: CupertinoIcons.hand_raised,
        title: 'Not now',
        body:
            'Tracend builds your plan with its own rules; the Coach chat stays off.',
        onTap: () => setState(() => _aiChoice = false),
      ),
    ],
  );

  Widget _pathSelection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Choose your starting point.',
        'Both paths end with a plan you approve before it starts.',
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

  static const _planMetrics = {
    HealthMetric.steps,
    HealthMetric.activeEnergy,
    HealthMetric.sleep,
    HealthMetric.workouts,
    HealthMetric.weight,
  };

  /// What the Apple Health step found, for the step and for Review.
  String _healthSummary() {
    final facts = _healthFacts;
    return switch (_healthImport) {
      'connected' when facts != null => [
        '${facts.daysWithData} of $onboardingHealthWindowDays days',
        // Only what the plan uses.
        HealthMetric.values
            .where(
              (metric) =>
                  facts.metrics.contains(metric) &&
                  _planMetrics.contains(metric),
            )
            .map((metric) => metric.label.toLowerCase())
            .join(', '),
      ].where((part) => part.isNotEmpty).join(' · '),
      'connected' => 'Connected',
      'empty' => 'Connected, but no data came back',
      'skipped' => 'Not connected',
      _ => 'Not answered',
    };
  }

  Widget _appleHealth() {
    final text = Theme.of(context).textTheme;
    final connected = _healthImport == 'connected';
    final empty = _healthImport == 'empty';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Connect Apple Health?',
          'Your plan can use the last 4 weeks from your iPhone and Apple Watch: steps, active energy, sleep, workouts and weight. Your plan works either way.',
        ),
        if (connected || empty)
          TracendCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  connected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.exclamationmark_circle,
                  color: connected
                      ? context.tracendColors.actionPrimary
                      : context.tracendColors.stateAttention,
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected
                            ? 'Apple Health connected'
                            : 'No Apple Health data came back',
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: TracendSpacing.xxs),
                      Text(
                        connected
                            ? '${_healthSummary()}. Next, your weight and daily activity show what it found; you confirm them.'
                            : 'If you expected data, open Settings › Health › Data Access & Devices › Tracend, turn the categories on, then try again. Or continue without it.',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_healthMessage != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              _healthMessage!,
              style: text.bodyMedium?.copyWith(
                color: context.tracendColors.stateAttention,
              ),
            ),
          ),
        ],
        const SizedBox(height: TracendSpacing.md),
        if (!connected)
          FilledButton.tonalIcon(
            onPressed: _healthBusy || _saving ? null : _connectHealth,
            icon: _healthBusy
                ? const TracendLoadingIndicator(size: 18)
                : const Icon(CupertinoIcons.heart_fill),
            label: Text(
              _healthBusy
                  ? 'Reading the last 4 weeks…'
                  : empty
                  ? 'Try again'
                  : 'Connect Apple Health',
            ),
          ),
        if (!connected && !empty)
          TextButton(
            onPressed: _healthBusy || _saving ? null : _skipHealth,
            child: const Text('Skip for now'),
          ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'Read-only: Tracend never writes to Apple Health. You can connect or refresh it later in Account.',
          style: text.bodySmall,
        ),
      ],
    );
  }

  bool get _goalHasTarget =>
      _goal == 'fat_loss' || _goal == 'muscle_gain' || _goal == 'recomposition';

  Widget _aboutYou() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'About you.',
        'Your calorie and protein targets are calculated from these.',
      ),
      _label('Sex'),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: _sexes.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.value),
                selected: _sex == entry.key,
                onSelected: (_) => setState(() => _sex = entry.key),
              ),
            )
            .toList(),
      ),
      if (_sex == 'unspecified')
        Padding(
          padding: const EdgeInsets.only(top: TracendSpacing.xs),
          child: Text(
            'Your calorie range will cover both estimates, so it is less precise.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      _label('Birth year'),
      TextField(
        key: const ValueKey('birth-year'),
        controller: _birthYear,
        keyboardType: TextInputType.number,
        maxLength: 4,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'e.g. 1994',
          counterText: '',
          border: const OutlineInputBorder(),
          errorText: _birthYear.text.length == 4 ? _birthYearError() : null,
        ),
      ),
      _label('Height: ${_heightCm.round()} cm'),
      Slider(
        value: _heightCm.clamp(120, 230),
        min: 120,
        max: 230,
        divisions: 110,
        label: '${_heightCm.round()} cm',
        onChanged: (value) => setState(() => _heightCm = value),
      ),
      _label('Current weight: ${_weightLabel(_weightKg)}'),
      if (_weightFromHealth && _healthFacts?.latestWeightDate != null)
        Text(
          'From Apple Health, ${_dayMonth(_healthFacts!.latestWeightDate!)}. Move the slider if it has changed.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      Slider(
        value: _weightKg.clamp(_minWeightKg, _maxWeightKg),
        min: _minWeightKg,
        max: _maxWeightKg,
        divisions: ((_maxWeightKg - _minWeightKg) * 2).round(),
        label: _weightLabel(_weightKg),
        onChanged: (value) => setState(() {
          _weightKg = value;
          _weightFromHealth = false;
        }),
      ),
      if (_goalHasTarget) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _targetWeightKg != null,
          onChanged: (on) =>
              setState(() => _targetWeightKg = on ? _weightKg : null),
          title: const Text('I have a target weight'),
        ),
        if (_targetWeightKg != null) ...[
          Text(
            'Target: ${_weightLabel(_targetWeightKg!)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _targetWeightKg!.clamp(_minWeightKg, _maxWeightKg),
            min: _minWeightKg,
            max: _maxWeightKg,
            divisions: ((_maxWeightKg - _minWeightKg) * 2).round(),
            label: _weightLabel(_targetWeightKg!),
            onChanged: (value) => setState(() => _targetWeightKg = value),
          ),
        ],
      ],
      _label('Outside training, your day is'),
      if (_healthFacts?.stepsPerDay case final steps?)
        Padding(
          padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
          child: Text(
            'Apple Health: about ${roundedSteps(steps)} steps a day over the last 4 weeks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      for (final entry in _activities.entries) ...[
        _ChoiceCard(
          selected: _dailyActivity == entry.key,
          icon: CupertinoIcons.person_crop_circle,
          title: entry.value.$1,
          body: entry.value.$2,
          tag:
              _healthFacts?.stepsPerDay != null &&
                  activityFromSteps(_healthFacts!.stepsPerDay!) == entry.key
              ? 'Matches your steps'
              : null,
          onTap: () => setState(() => _dailyActivity = entry.key),
        ),
        const SizedBox(height: TracendSpacing.xs),
      ],
    ],
  );

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _dayMonth(DateTime date) =>
      '${date.day} ${_months[date.month - 1]}';

  static String _weightLabel(double kg) {
    final rounded = _half(kg);
    return '${rounded % 1 == 0 ? rounded.toInt() : rounded} kg';
  }

  Widget _schedule() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'When do you train?',
        'Pick your training days; keep at least one rest day.',
      ),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          for (var day = 1; day <= 7; day++)
            FilterChip(
              label: Text(onboardingWeekdayLabels[day - 1]),
              selected: _weekdays.contains(day),
              onSelected: (on) => setState(() {
                if (!on) {
                  _weekdays = {..._weekdays}..remove(day);
                } else if (_weekdays.length < _maxTrainingDays) {
                  _weekdays = {..._weekdays, day};
                } else {
                  _error = 'Up to six training days; keep one for rest.';
                }
              }),
            ),
        ],
      ),
      const SizedBox(height: TracendSpacing.xs),
      Text(
        '${_weekdays.length} ${_weekdays.length == 1 ? 'day' : 'days'} a week',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _label('Session length: $_sessionMinutes minutes'),
      Slider(
        value: _sessionMinutes.toDouble().clamp(30, 120),
        min: 30,
        max: 120,
        divisions: 6,
        label: '$_sessionMinutes minutes',
        onChanged: (value) => setState(() => _sessionMinutes = value.round()),
      ),
    ],
  );

  Widget _equipmentSelection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'What can you train with?',
        'Your plan uses only exercises this equipment allows. Choose none for bodyweight only.',
      ),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: _equipmentChoices.entries
            .map(
              (entry) => FilterChip(
                label: Text(entry.value),
                selected: _equipment.contains(entry.key),
                onSelected: (on) => setState(
                  () => _equipment = on
                      ? {..._equipment, entry.key}
                      : ({..._equipment}..remove(entry.key)),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: TracendSpacing.xs),
      Text(
        _equipment.isEmpty
            ? 'Bodyweight only'
            : '${_equipment.length} selected',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _equipmentNote,
        'Anything else about your equipment',
        'Example: dumbbells up to 20 kg',
        required: false,
      ),
    ],
  );

  Widget _foodAndLimits() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Food and limits.',
        'Your coach plans around these, in your own words.',
      ),
      _field(
        _nutrition,
        'Diet',
        'Diet pattern, allergies, dislikes, meal schedule',
      ),
      const SizedBox(height: TracendSpacing.md),
      _label('Movements to avoid'),
      Text(
        'Your plan never includes these. Leave all off if none.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: TracendSpacing.xs),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: _avoidChoices.entries
            .map(
              (entry) => FilterChip(
                label: Text(entry.value),
                selected: _avoid.contains(entry.key),
                onSelected: (on) => setState(
                  () => _avoid = on
                      ? {..._avoid, entry.key}
                      : ({..._avoid}..remove(entry.key)),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _constraints,
        'Other limitations or dislikes',
        'Optional: anything else your coach should know',
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
    maxLength: 500,
    decoration: InputDecoration(
      labelText: required ? '$label *' : label,
      helperText: helper,
      helperMaxLines: 2,
      counterText: '',
      border: const OutlineInputBorder(),
    ),
  );

  Widget _review() {
    final weekdays = _weekdays.toList()..sort();
    final days = weekdays.map((day) => onboardingWeekdayLabels[day - 1]);
    final target = _targetWeightKg == null
        ? ''
        : ' → ${_weightLabel(_targetWeightKg!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Review before building.',
          'Your plan is built from these answers and checked against Tracend\'s safety ranges.',
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
              _ReviewRow('Apple Health', _healthSummary()),
              const Divider(height: TracendSpacing.xl),
              _ReviewRow(
                'You',
                '${_sexes[_sex] ?? '—'} · born ${_birthYear.text} · '
                    '${_heightCm.round()} cm · ${_weightLabel(_weightKg)}$target',
              ),
              const Divider(height: TracendSpacing.xl),
              _ReviewRow(
                'Schedule',
                '${days.join(', ')} · $_sessionMinutes min',
              ),
              const Divider(height: TracendSpacing.xl),
              _ReviewRow(
                'Equipment',
                _equipment.isEmpty
                    ? 'Bodyweight only'
                    : (_equipment.toList()..sort())
                          .map((item) => _equipmentChoices[item]!)
                          .join(', '),
              ),
              if (_avoid.isNotEmpty) ...[
                const Divider(height: TracendSpacing.xl),
                _ReviewRow(
                  'Avoid',
                  _avoidChoices.entries
                      .where((entry) => _avoid.contains(entry.key))
                      .map((entry) => entry.value)
                      .join(', '),
                ),
              ],
              if (_path == 'experienced') ...[
                const Divider(height: TracendSpacing.xl),
                _ReviewRow('Keep', _currentPlan.text),
              ],
            ],
          ),
        ),
        if (_revisionNote.text.trim().isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.md),
          _field(
            _revisionNote,
            'What should change',
            'Sent with your next plan request',
            required: false,
          ),
        ],
        const SizedBox(height: TracendSpacing.md),
        Text(
          'Building creates a proposal only. Nothing starts until you approve it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _plan() {
    final proposal = _proposal;
    if (proposal != null) {
      return OnboardingProposalView(
        proposal: proposal,
        saving: _saving,
        error: _error,
        onApprove: () => _respond('accept'),
        onRequestRevision: _requestRevision,
        onReject: () => _respond('reject'),
      );
    }
    if (_proposalExpired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'This plan proposal expired.',
            'Proposals last seven days, so the plan you approve matches your current answers. Your answers are saved; build a fresh plan from them.',
          ),
          FilledButton(
            onPressed: _saving ? null : _buildPlan,
            child: const Text('Build a new plan'),
          ),
          TextButton(
            onPressed: _saving ? null : _back,
            child: const Text('Back to review'),
          ),
        ],
      );
    }
    if (_generationFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Your plan was not built.',
            'Something went wrong while building it. Your answers are saved.',
          ),
          FilledButton(
            onPressed: _saving ? null : _buildPlan,
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: _saving ? null : _back,
            child: const Text('Back to review'),
          ),
        ],
      );
    }
    return Column(
      children: [
        const SizedBox(height: TracendSpacing.xl),
        const TracendLoadingIndicator(size: 32),
        const SizedBox(height: TracendSpacing.lg),
        Text(
          'Building your plan',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'This can take up to a minute. You can leave the app; your plan will be here when you come back.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _RevisionSheet extends StatefulWidget {
  const _RevisionSheet();

  @override
  State<_RevisionSheet> createState() => _RevisionSheetState();
}

class _RevisionSheetState extends State<_RevisionSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      TracendSpacing.gutter,
      TracendSpacing.gutter,
      TracendSpacing.gutter,
      TracendSpacing.gutter + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What should change?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: TracendSpacing.sm),
        TextField(
          controller: _note,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Example: fewer exercises per session, no deadlifts',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: const Text('Request changes'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.tag,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  /// A short fact shown under the body, such as what Apple Health suggests.
  final String? tag;

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
                    if (tag != null)
                      Padding(
                        padding: const EdgeInsets.only(top: TracendSpacing.xxs),
                        child: Text(
                          tag!,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: context.tracendColors.actionPrimary,
                              ),
                        ),
                      ),
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
