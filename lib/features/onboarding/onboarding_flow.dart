import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/onboarding/health_activity.dart';
import 'package:tracend/features/onboarding/onboarding_proposal_view.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

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
    this.healthBaseline,
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

  /// The athlete's usual months from Apple Health, read after Connect.
  final HealthBaselineSource? healthBaseline;
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
    'Your training',
    'Current lifts',
    'Focus',
    'Review',
    'Coach questions',
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
    'training',
    'lifts',
    'focus',
    'review',
    'questions',
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
  static const _trainingStep = 9;
  static const _liftsStep = 10;
  static const _focusStep = 11;
  static const _reviewStep = 12;
  static const _questionsStep = 13;
  static const _proposalStep = 14;

  /// How long the questions or the plan wait for the usual months to be sent
  /// before going ahead without them.
  static const _baselineWait = Duration(seconds: 30);

  static const _goals = <String, (String, String)>{
    'fat_loss': (
      'Fat loss',
      'Lose fat while keeping your strength and muscle.',
    ),
    'muscle_gain': (
      'Muscle gain',
      'Build muscle with a small calorie surplus.',
    ),
    'recomposition': (
      'Recomposition',
      'Lose fat and build muscle at about the same weight.',
    ),
    'strength': ('Strength', 'Lift heavier on the main movements.'),
    'aesthetic': (
      'Aesthetic emphasis',
      'Shape and balance how your body looks.',
    ),
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

  static const _trainingYears = <String, String>{
    'under_1': 'Under a year',
    '1_2': '1–2 years',
    '3_5': '3–5 years',
    'over_5': 'Over 5 years',
  };

  /// The barbell lifts a top set can be reported for; the load is the whole
  /// bar, so the server can estimate a one-rep max and starting loads.
  static const _lifts = <String, String>{
    'barbell-bench-press': 'Bench press',
    'barbell-back-squat': 'Back squat',
    'barbell-deadlift': 'Deadlift',
    'barbell-overhead-press': 'Overhead press',
    'barbell-row': 'Barbell row',
  };

  /// The catalog's target muscles, in catalog order.
  static const _muscles = <String, String>{
    'quads': 'Quads',
    'glutes': 'Glutes',
    'hamstrings': 'Hamstrings',
    'chest': 'Chest',
    'back': 'Back',
    'shoulders': 'Shoulders',
    'biceps': 'Biceps',
    'triceps': 'Triceps',
    'core': 'Core',
    'calves': 'Calves',
  };
  static const _maxPriorityMuscles = 2;
  static const _maxStrongMuscles = 3;

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
    'training_years': 'training years',
    'goal': 'goal',
    'path': 'starting point',
  };

  final _birthYear = TextEditingController();
  final _equipmentNote = TextEditingController();
  final _nutrition = TextEditingController(text: 'No dietary restrictions');
  final _constraints = TextEditingController();
  final _currentPlan = TextEditingController();
  final _trainingHistory = TextEditingController();
  final _revisionNote = TextEditingController();
  bool _loading = true;

  /// The saved answers could not be loaded. Nothing can be saved until they
  /// are, so a retry never overwrites them with defaults.
  bool _restoreFailed = false;
  bool _saving = false;
  bool _signingOut = false;

  /// Editing one answer from Review: Continue returns to Review.
  bool _returnToReview = false;

  /// The approved proposal, shown once as "You're set" before the app opens.
  OnboardingProposal? _approved;
  bool _adult = false;
  bool _needsClinicalSupport = false;
  bool _terms = false;
  bool _privacy = false;
  bool? _aiChoice;

  /// The answer already stored, so passing the step again adds no record.
  bool? _aiRecorded;
  int _step = _eligibilityStep;
  String? _path;

  /// Chosen on the Goal step; nothing is preselected.
  String? _goal;
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

  /// The athlete's usual months, read after Apple Health connects.
  HealthBaseline? _baseline;
  bool _baselineBusy = false;

  /// The read of the usual months in progress; a second caller joins it.
  Future<void>? _baselineRead;

  /// The usual months were sent this session (or Apple Health had none to
  /// read), so questions and the plan can be built with them.
  bool _baselineSent = false;

  /// How long the athlete has trained (experienced path).
  String? _years;

  /// Reported top sets by lift slug.
  Map<String, _LiftEntry> _liftEntries = {};
  Set<String> _priority = {};
  Set<String> _strong = {};

  /// The coach's questions for the answers named by [_followUpsHash]; the
  /// athlete's answers are kept by question.
  List<FollowUpQuestion> _questions = const [];
  String? _followUpsHash;
  Map<String, String> _followUpAnswers = {};
  bool _asking = false;

  /// Bumped to ignore a question request still running (Skip, Back).
  int _questionsRun = 0;

  /// The latest question request, settled either way; the plan starts only
  /// after it, so the two never spend the athlete's AI budget at once.
  Future<void> _questionsCall = Future.value();

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
    _trainingHistory.dispose();
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
      if (_path == 'experienced') ...{
        'current_plan': _currentPlan.text.trim(),
        'training_years': ?_years,
        'training_history': _trainingHistory.text.trim(),
        'current_lifts': [
          for (final slug in _lifts.keys)
            if (_liftEntries[slug] case final entry?) entry.toJson(slug),
        ],
      },
      'priority_muscles': _muscles.keys.where(_priority.contains).toList(),
      'strong_muscles': _muscles.keys.where(_strong.contains).toList(),
      if (_followUpsHash != null) ...{
        'follow_ups_hash': _followUpsHash,
        'follow_ups': [
          for (final question in _questions)
            if (_followUpAnswers[question.question]?.trim() case final answer?
                when answer.isNotEmpty)
              {
                'category': question.category,
                'question': question.question,
                'answer': answer,
              },
        ],
      },
      if (_revisionNote.text.trim().isNotEmpty)
        'revision_note': _revisionNote.text.trim(),
    };
  }

  /// The training and lifts steps are for the experienced path only.
  bool _skips(int step) =>
      _path != 'experienced' && (step == _trainingStep || step == _liftsStep);

  int _after(int step) {
    var next = step + 1;
    while (_skips(next)) {
      next++;
    }
    return next;
  }

  int _before(int step) {
    var previous = step - 1;
    while (previous > 0 && _skips(previous)) {
      previous--;
    }
    return previous;
  }

  /// The steps this athlete sees, for "Step N of M".
  List<int> get _visibleSteps => [
    for (var step = 0; step < _sections.length; step++)
      if (!_skips(step)) step,
  ];

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
      final draft = await widget.repository.loadDraft().timeout(
        const Duration(seconds: 15),
      );
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
        final years = payload['training_years'];
        if (_trainingYears.containsKey(years)) _years = years as String;
        _trainingHistory.text = payload['training_history'] as String? ?? '';
        _liftEntries = {
          for (final item in payload['current_lifts'] as List? ?? const [])
            if (item is Map && _lifts.containsKey(item['slug']))
              item['slug'] as String: _LiftEntry.fromJson(item),
        };
        List<String> muscles(Object? value) => (value as List? ?? const [])
            .whereType<String>()
            .where(_muscles.containsKey)
            .toList();
        _priority = muscles(
          payload['priority_muscles'],
        ).take(_maxPriorityMuscles).toSet();
        _strong = muscles(
          payload['strong_muscles'],
        ).take(_maxStrongMuscles).toSet();
        if (payload['follow_ups_hash'] case final String hash) {
          _followUpsHash = hash;
          _followUpAnswers = {
            for (final item in payload['follow_ups'] as List? ?? const [])
              if (item is Map &&
                  item['question'] is String &&
                  item['answer'] is String)
                item['question'] as String: item['answer'] as String,
          };
        }
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
        if (_skips(restored)) restored = _focusStep;
        if (restored > 0) _step = restored;
        _aboutPassed = _step > _aboutStep;
        resumeGeneration = _step == _proposalStep;
      }
      _restoreFailed = false;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      _restoreFailed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (_restoreFailed) return;
    if (resumeGeneration && mounted) unawaited(_resumeGeneration());
    if (_step == _questionsStep && mounted) unawaited(_fetchQuestions());
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
      if (_healthImport == 'connected' && _step <= _reviewStep) {
        unawaited(_loadBaseline());
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }

  /// Reads the usual months and sends them, so the plan can compare them
  /// with the last 4 weeks. Never blocks the step; a read already running is
  /// joined.
  Future<void> _loadBaseline() {
    final source = widget.healthBaseline;
    if (source == null) return Future.value();
    return _baselineRead ??= _readBaseline(
      source,
    ).whenComplete(() => _baselineRead = null);
  }

  Future<void> _readBaseline(HealthBaselineSource source) async {
    if (mounted) setState(() => _baselineBusy = true);
    try {
      final baseline = await source.load();
      _baselineSent = true;
      if (mounted) setState(() => _baseline = baseline);
    } catch (e) {
      debugPrint('Non-critical error: $e');
    } finally {
      if (mounted) setState(() => _baselineBusy = false);
    }
  }

  /// The questions and the plan are hashed with the usual months. With Apple
  /// Health connected they wait for the months to be sent, retrying a read
  /// that failed or never ran (a restored draft), so an upload landing
  /// between the questions and the plan never discards the follow-up answers.
  Future<void> _awaitBaseline() async {
    if (_baselineSent || _healthImport != 'connected') return;
    try {
      await _loadBaseline().timeout(_baselineWait);
    } on TimeoutException catch (e) {
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
      if (_healthImport == 'connected') unawaited(_loadBaseline());
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

  Future<void> _retryRestore() async {
    setState(() {
      _loading = true;
      _restoreFailed = false;
    });
    await _restore();
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut?.call();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
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
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _proposal = null;
      _generationFailed = false;
      _proposalExpired = false;
    });
    try {
      // A skipped question request still running finishes first (the app
      // gives up on it after 45 s).
      await _questionsCall;
      await _awaitBaseline();
      if (!mounted) return;
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
    } catch (error) {
      if (!mounted) return;
      if (!_showPlanRefusal(error)) {
        debugPrint('Non-critical error: $error');
        setState(() {
          _saving = false;
          _error =
              'Your plan could not be started. Check the connection and try again.';
        });
      }
    }
  }

  /// Shows why the plan builder refused these answers and opens the step to
  /// change; false for any other error.
  bool _showPlanRefusal(Object error) {
    switch (error) {
      case OnboardingAnswersIncomplete(:final missing):
        final labels = missing.map((key) => _fieldLabels[key] ?? key);
        setState(() {
          _saving = false;
          _asking = false;
          _step = _stepForMissing(missing);
          _error = missing.length == 1 && missing.first == 'avoid_patterns'
              ? 'You wrote a limitation. Choose the movements your plan should leave out, or none, then build your plan.'
              : 'Add your ${labels.join(', ')} to build your plan.';
        });
        return true;
      case OnboardingPlanUnavailable():
        setState(() {
          _saving = false;
          _asking = false;
          _step = _reviewStep;
          _error = 'The plan builder is unavailable. Try again in a minute.';
        });
        return true;
      case OnboardingPlanInfeasible(:final change):
        setState(() {
          _saving = false;
          _asking = false;
          _step = change.contains('avoid_patterns')
              ? _foodStep
              : _stepForMissing(change);
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
        return true;
      default:
        return false;
    }
  }

  /// Review → the coach's questions: the answers are saved, then the coach
  /// may ask up to three questions before the plan is built.
  Future<void> _askQuestions() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveDraft(
        path: _path,
        currentSection: _sectionKeys[_questionsStep],
        payload: _payload,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'This section could not be saved. Check the connection and try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _step = _questionsStep;
    });
    await _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    final run = ++_questionsRun;
    setState(() {
      _asking = true;
      _questions = const [];
    });
    await _awaitBaseline();
    if (!mounted || run != _questionsRun) return;
    try {
      final call = widget.repository.askQuestions();
      _questionsCall = call.then<void>((_) {}, onError: (Object _) {});
      final result = await call;
      if (!mounted || run != _questionsRun) return;
      setState(() {
        // Answers carry over only to questions asked for the same answers.
        if (result.hash != _followUpsHash) _followUpAnswers = {};
        _followUpsHash = result.hash;
        _questions = result.questions;
        _asking = false;
      });
      if (result.questions.isEmpty) await _buildPlan();
    } catch (error) {
      if (!mounted || run != _questionsRun) return;
      if (_showPlanRefusal(error)) return;
      // Questions are optional: without them the plan is built from the answers.
      debugPrint('Non-critical error: $error');
      setState(() => _asking = false);
      await _buildPlan();
    }
  }

  int _stepForMissing(List<String> missing) {
    if (missing.contains('path')) return _pathStep;
    if (missing.contains('current_plan') ||
        missing.contains('training_years')) {
      return _trainingStep;
    }
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
      await _askQuestions();
      return;
    }
    if (_step == _questionsStep) {
      // Building now: a question request still running is ignored.
      _questionsRun++;
      setState(() => _asking = false);
      await _buildPlan();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_step == _eligibilityStep) {
        await widget.repository.recordEligibilityAndConsent(eligible: true);
      }
      if (_step == _aiStep && _aiChoice != _aiRecorded) {
        await widget.aiConsent?.record(granted: _aiChoice!);
        _aiRecorded = _aiChoice;
      }
      if (_step == _goalStep) await widget.repository.saveGoal(_goal!);
      if (_step == _foodStep) _avoidAnswered = true;
      if (_step == _aboutStep) _aboutPassed = true;
      // Changed answers get new questions; old follow-up answers no longer fit.
      _followUpsHash = null;
      _followUpAnswers = {};
      final next = _returnToReview ? _reviewStep : _after(_step);
      await widget.repository.saveDraft(
        path: _path,
        currentSection: _sectionKeys[next],
        payload: _payload,
      );
      if (!mounted) return;
      setState(() {
        _step = next;
        _returnToReview = false;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
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
    _goalStep => _goal != null,
    _healthStep => _healthImport != null && !_healthBusy,
    _aboutStep =>
      _sex != null && _dailyActivity != null && _birthYearError() == null,
    _scheduleStep => _weekdays.isNotEmpty,
    _foodStep => _nutrition.text.trim().isNotEmpty,
    _trainingStep => _years != null && _currentPlan.text.trim().isNotEmpty,
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
      _goalStep => 'Choose what your first block should prioritize.',
      _healthStep => 'Connect Apple Health, or choose Skip for now.',
      _aboutStep =>
        _sex == null
            ? 'Choose an option for sex.'
            : _dailyActivity == null
            ? 'Choose how active you are outside training.'
            : _birthYearError()!,
      _scheduleStep => 'Choose at least one training day.',
      _trainingStep =>
        _years == null
            ? 'Choose how long you have trained.'
            : 'Describe your current plan.',
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
      if (!mounted) return;
      if (action == 'accept') {
        setState(() {
          _approved = proposal;
          _proposal = null;
        });
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
      if (!mounted) return;
      setState(() {
        _error = 'Your response was not saved. Nothing has changed; try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _sheetOpen = false;

  Future<void> _requestRevision() async {
    if (_sheetOpen || _saving) return;
    _sheetOpen = true;
    final String? note;
    try {
      note = await showTracendSheet<String>(
        context,
        title: 'What should change?',
        subtitle: 'Sent with your next plan request.',
        builder: (_) => const _RevisionSheet(),
      );
    } finally {
      _sheetOpen = false;
    }
    if (note == null || note.isEmpty || !mounted) return;
    await _respond('request_revision', note: note);
  }

  Future<void> _confirmReject() async {
    if (_sheetOpen || _saving) return;
    _sheetOpen = true;
    final bool confirmed;
    try {
      confirmed = await showTracendConfirm(
        context,
        title: 'Reject this plan?',
        message:
            'Nothing starts. Your answers stay saved, and you can build a new plan from them.',
        confirmLabel: 'Reject plan',
        cancelLabel: 'Keep reviewing',
        destructive: true,
      );
    } finally {
      _sheetOpen = false;
    }
    if (confirmed && mounted) await _respond('reject');
  }

  /// Opens one step from Review; Continue there returns to Review.
  void _editFromReview(int step) {
    _pollRun++;
    setState(() {
      _returnToReview = true;
      _error = null;
      _step = step;
    });
  }

  void _back() {
    _pollRun++;
    _questionsRun++;
    setState(() {
      _returnToReview = false;
      _generating = false;
      _generationFailed = false;
      _proposalExpired = false;
      _asking = false;
      _error = null;
      _step = _step == _proposalStep || _step == _questionsStep
          ? _reviewStep
          : _before(_step);
    });
  }

  List<Widget> _signOutAction() => [
    if (widget.onSignOut != null)
      TextButton(
        onPressed: _saving || _signingOut ? null : _signOut,
        child: const Text('Sign out'),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading || _restoreFailed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Set up Tracend'),
          actions: _signOutAction(),
        ),
        body: SafeArea(
          child: Center(
            child: _loading
                ? const TracendLoader(
                    size: 36,
                    semanticLabel: 'Loading your saved answers',
                  )
                : Padding(
                    padding: const EdgeInsets.all(TracendSpacing.gutter),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _heading(
                          'Your answers did not load.',
                          'They are still saved. Check the connection and try again; nothing is saved until they load.',
                        ),
                        FilledButton(
                          onPressed: _retryRestore,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }
    if (_approved != null) return _done(_approved!);
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
        actions: _signOutAction(),
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
                    'Step $_stepNumber of ${_visibleSteps.length} · ${_sections[_step]}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  _StepLine(count: _visibleSteps.length, current: _stepNumber),
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
                      '$_step-${_proposal?.id}-$_generating-$_generationFailed-$_proposalExpired-$_asking',
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
                          ? const TracendLoader(
                              size: 24,
                              semanticLabel: 'Saving',
                            )
                          : Text(
                              _step == _reviewStep
                                  ? 'Continue to your coach'
                                  : _step == _questionsStep
                                  ? (_asking
                                        ? 'Skip and build my plan'
                                        : 'Build my plan')
                                  : _returnToReview
                                  ? 'Save and return to review'
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
    _trainingStep => _training(),
    _liftsStep => _currentLifts(),
    _focusStep => _focus(),
    _reviewStep => _review(),
    _questionsStep => _coachQuestions(),
    _ => _plan(),
  };

  /// The step's position among the steps this athlete sees.
  int get _stepNumber => _visibleSteps.indexOf(_step) + 1;

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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'First, confirm the boundary.',
        'Tracend supports healthy adults. It is not medical, pregnancy, rehabilitation, or eating-disorder care.',
      ),
      TracendGroupedList(
        children: [
          _CheckRow(
            title: 'I am 18 or older',
            checked: _adult,
            onChanged: (value) => setState(() => _adult = value),
          ),
          MergeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TracendListRow.minHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TracendListRow.horizontalPadding,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'I need clinical nutrition, pregnancy, acute injury, or rehabilitation support',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: TracendSpacing.sm),
                    Switch.adaptive(
                      value: _needsClinicalSupport,
                      onChanged: (value) =>
                          setState(() => _needsClinicalSupport = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: TracendSpacing.lg),
      TracendGroupedList(
        children: [
          _CheckRow(
            title: 'I accept the private-beta terms',
            checked: _terms,
            onChanged: (value) => setState(() => _terms = value),
          ),
          _CheckRow(
            title: 'I have read the privacy notice',
            checked: _privacy,
            onChanged: (value) => setState(() => _privacy = value),
          ),
        ],
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
        icon: CupertinoIcons.chat_bubble_text,
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
      for (final entry in _goals.entries) ...[
        _ChoiceCard(
          selected: _goal == entry.key,
          title: entry.value.$1,
          body: entry.value.$2,
          onTap: () => setState(() => _goal = entry.key),
        ),
        const SizedBox(height: TracendSpacing.xs),
      ],
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
          'Your plan can use the last 4 weeks from your iPhone and Apple Watch (steps, active energy, sleep, workouts and weight) and compare them with your usual months. Your plan works either way.',
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
                      if (connected && _baselineBusy) ...[
                        const SizedBox(height: TracendSpacing.xs),
                        Text(
                          'Reading your usual months…',
                          style: text.bodySmall,
                        ),
                      ],
                      if (connected)
                        for (final line in _baselineLines())
                          Padding(
                            padding: const EdgeInsets.only(
                              top: TracendSpacing.xs,
                            ),
                            child: Text(line, style: text.bodyMedium),
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
          OutlinedButton.icon(
            onPressed: _healthBusy || _saving ? null : _connectHealth,
            icon: _healthBusy
                ? const TracendLoader(
                    size: 20,
                    semanticLabel: 'Reading Apple Health',
                  )
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
      _SingleChoice<String>(
        label: 'Sex',
        options: [for (final entry in _sexes.entries) (entry.key, entry.value)],
        // Nothing is selected until the athlete answers.
        selected: _sex,
        onChanged: (value) => setState(() => _sex = value),
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
        textInputAction: TextInputAction.done,
        maxLength: 4,
        // The iOS number pad has no Done key: a tap outside or the fourth
        // digit closes it, so it never covers the rest of the step.
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        onChanged: (value) {
          if (value.length == 4) FocusScope.of(context).unfocus();
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'e.g. 1994',
          counterText: '',
          errorText: _birthYear.text.length == 4 ? _birthYearError() : null,
        ),
      ),
      _label('Height: ${_heightCm.round()} cm'),
      _Stepper(
        label: 'Height',
        value: _heightCm.roundToDouble().clamp(120, 230),
        min: 120,
        max: 230,
        step: 1,
        format: (value) => '${value.round()} cm',
        onChanged: (value) => setState(() => _heightCm = value),
      ),
      _label('Current weight: ${_weightLabel(_weightKg)}'),
      if (_weightFromHealth && _healthFacts?.latestWeightDate != null)
        Text(
          'From Apple Health, ${_dayMonth(_healthFacts!.latestWeightDate!)}. Move the slider if it has changed.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      _Stepper(
        label: 'Current weight',
        value: _half(_weightKg).clamp(_minWeightKg, _maxWeightKg),
        min: _minWeightKg,
        max: _maxWeightKg,
        step: 0.5,
        format: _weightLabel,
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
          _Stepper(
            label: 'Target weight',
            value: _half(_targetWeightKg!).clamp(_minWeightKg, _maxWeightKg),
            min: _minWeightKg,
            max: _maxWeightKg,
            step: 0.5,
            format: _weightLabel,
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
      _Stepper(
        label: 'Session length',
        value: _sessionMinutes.toDouble().clamp(30, 120),
        min: 30,
        max: 120,
        step: 15,
        format: (value) => '${value.round()} minutes',
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
    ],
  );

  Widget _training() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Your training so far.',
        'A coach starts from what you have done. Your plan keeps what works.',
      ),
      _label('How long have you trained consistently?'),
      Wrap(
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: _trainingYears.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.value),
                selected: _years == entry.key,
                onSelected: (_) => setState(() => _years = entry.key),
              ),
            )
            .toList(),
      ),
      if (_years == 'under_1')
        Padding(
          padding: const EdgeInsets.only(top: TracendSpacing.xs),
          child: Text(
            'Under a year keeps beginner effort and volume limits.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _currentPlan,
        'Current plan',
        'Your split, days, main lifts and sets, and how you have kept to it',
      ),
      const SizedBox(height: TracendSpacing.md),
      _field(
        _trainingHistory,
        'What has worked, and what has stalled',
        'Example: legs grow easily; bench stuck at 80 kg for two months',
        required: false,
      ),
    ],
  );

  Widget _currentLifts() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Recent top sets.',
        'Optional. Add a recent hard set for the barbell lifts you do: the weight on the bar, the reps, and how many more you could have done. Tracend estimates your strength and sets starting weights from it.',
      ),
      for (final entry in _lifts.entries) ...[
        _LiftCard(
          name: entry.value,
          entry: _liftEntries[entry.key],
          onChanged: (value) => setState(() {
            _liftEntries = {..._liftEntries};
            if (value == null) {
              _liftEntries.remove(entry.key);
            } else {
              _liftEntries[entry.key] = value;
            }
          }),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
    ],
  );

  Widget _muscleChips(
    Set<String> selected,
    int max,
    ValueChanged<Set<String>> onChanged,
  ) => Wrap(
    spacing: TracendSpacing.xs,
    runSpacing: TracendSpacing.xs,
    children: _muscles.entries
        .map(
          (entry) => FilterChip(
            label: Text(entry.value),
            selected: selected.contains(entry.key),
            onSelected: (on) {
              if (on && selected.length >= max) {
                setState(
                  () => _error =
                      'Choose at most $max. Focusing on everything is focusing on nothing.',
                );
                return;
              }
              setState(() => _error = null);
              onChanged(
                on
                    ? {...selected, entry.key}
                    : ({...selected}..remove(entry.key)),
              );
            },
          ),
        )
        .toList(),
  );

  Widget _focus() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Where should the plan focus?',
        'Optional. Pick at most two muscles to bring up: they get more weekly sets, taken from the others. Focusing on everything is focusing on nothing.',
      ),
      _label('Bring up'),
      _muscleChips(
        _priority,
        _maxPriorityMuscles,
        (value) => setState(() {
          _priority = value;
          _strong = {..._strong}..removeAll(value);
        }),
      ),
      _label('Already strong'),
      Text(
        'Optional, up to three. Your coach keeps these in maintenance.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: TracendSpacing.xs),
      _muscleChips(
        _strong,
        _maxStrongMuscles,
        (value) => setState(() {
          _strong = value;
          _priority = {..._priority}..removeAll(value);
        }),
      ),
    ],
  );

  Widget _coachQuestions() {
    final text = Theme.of(context).textTheme;
    // Skipped while the coach was reading: the plan starts once it finishes.
    final building = !_asking && _saving && _questions.isEmpty;
    if (_asking || building) {
      return Column(
        children: [
          const SizedBox(height: TracendSpacing.xl),
          TracendLoader(
            size: 36,
            semanticLabel: building
                ? 'Building your plan'
                : 'Your coach is reading your answers',
          ),
          const SizedBox(height: TracendSpacing.lg),
          Text(
            building
                ? 'Building your plan'
                : 'Your coach is reading your answers',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            building
                ? 'It starts as soon as your coach has finished reading.'
                : 'It may ask a few questions before building your plan. Usually under 30 seconds; you can skip.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'A few questions from your coach.',
          'Answer what you can; anything left blank is fine.',
        ),
        for (final question in _questions) ...[
          _QuestionCard(
            question: question,
            answer: _followUpAnswers[question.question] ?? '',
            onChanged: (answer) => setState(
              () => _followUpAnswers = {
                ..._followUpAnswers,
                question.question: answer,
              },
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
      ],
    );
  }

  /// The usual-vs-recent lines on the Apple Health step.
  List<String> _baselineLines() {
    final baseline = _baseline;
    if (baseline == null) return const [];
    String sleep(int minutes) => '${minutes ~/ 60} h ${minutes % 60} min';
    String times(double value) =>
        '${value % 1 == 0 ? value.toInt() : value}× a week';
    return [
      if (baseline.usualStrengthPerWeek case final usual?)
        'Strength: ${times(usual)} usually'
            '${baseline.recentStrengthPerWeek == null ? '' : ' · ${times(baseline.recentStrengthPerWeek!)} lately'}',
      if (baseline.usualSleepMinutes case final usual?)
        'Sleep: ${sleep(usual)} usually'
            '${_healthFacts?.sleepMinutesPerNight == null ? '' : ' · ${sleep(_healthFacts!.sleepMinutesPerNight!)} lately'}',
      if (!baseline.hasUsual)
        'Fewer than 3 earlier months of data, so your plan uses the last 4 weeks.',
    ];
  }

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
    ),
  );

  List<_ReviewRow> _reviewRows() {
    final weekdays = _weekdays.toList()..sort();
    final days = weekdays.map((day) => onboardingWeekdayLabels[day - 1]);
    final target = _targetWeightKg == null
        ? ''
        : ' → ${_weightLabel(_targetWeightKg!)}';
    String orNone(String value) => value.trim().isEmpty ? 'None' : value.trim();
    return [
      _ReviewRow(
        'Path',
        _path == 'experienced' ? 'Preserve what works' : 'Guide me',
        onEdit: () => _editFromReview(_pathStep),
      ),
      _ReviewRow(
        'Goal',
        _goals[_goal]?.$1 ?? 'Not chosen',
        onEdit: () => _editFromReview(_goalStep),
      ),
      _ReviewRow(
        'Apple Health',
        _healthSummary(),
        onEdit: () => _editFromReview(_healthStep),
      ),
      _ReviewRow(
        'You',
        '${_sexes[_sex] ?? '—'} · born ${_birthYear.text} · '
            '${_heightCm.round()} cm · ${_weightLabel(_weightKg)}$target',
        onEdit: () => _editFromReview(_aboutStep),
      ),
      _ReviewRow(
        'Daily activity',
        _activities[_dailyActivity]?.$1 ?? 'Not chosen',
        onEdit: () => _editFromReview(_aboutStep),
      ),
      _ReviewRow(
        'Schedule',
        '${days.join(', ')} · $_sessionMinutes min',
        onEdit: () => _editFromReview(_scheduleStep),
      ),
      _ReviewRow(
        'Equipment',
        [
          if (_equipment.isEmpty)
            'Bodyweight only'
          else
            (_equipment.toList()..sort())
                .map((item) => _equipmentChoices[item]!)
                .join(', '),
          if (_equipmentNote.text.trim().isNotEmpty) _equipmentNote.text.trim(),
        ].join(' · '),
        onEdit: () => _editFromReview(_equipmentStep),
      ),
      _ReviewRow(
        'Diet',
        orNone(_nutrition.text),
        onEdit: () => _editFromReview(_foodStep),
      ),
      _ReviewRow(
        'Avoid',
        _avoid.isEmpty
            ? 'None'
            : _avoidChoices.entries
                  .where((entry) => _avoid.contains(entry.key))
                  .map((entry) => entry.value)
                  .join(', '),
        onEdit: () => _editFromReview(_foodStep),
      ),
      _ReviewRow(
        'Limitations',
        orNone(_constraints.text),
        onEdit: () => _editFromReview(_foodStep),
      ),
      if (_path == 'experienced') ...[
        _ReviewRow(
          'Training',
          [
            _trainingYears[_years] ?? 'Years not chosen',
            orNone(_currentPlan.text),
            if (_trainingHistory.text.trim().isNotEmpty)
              _trainingHistory.text.trim(),
          ].join(' · '),
          onEdit: () => _editFromReview(_trainingStep),
        ),
        _ReviewRow(
          'Top sets',
          _liftEntries.isEmpty
              ? 'None'
              : [
                  for (final entry in _lifts.entries)
                    if (_liftEntries[entry.key] case final lift?)
                      '${entry.value} ${lift.summary}',
                ].join(' · '),
          onEdit: () => _editFromReview(_liftsStep),
        ),
      ],
      _ReviewRow(
        'Focus',
        [
          _priority.isEmpty
              ? 'No focus'
              : 'Bring up ${_muscles.entries.where((entry) => _priority.contains(entry.key)).map((entry) => entry.value.toLowerCase()).join(', ')}',
          if (_strong.isNotEmpty)
            'strong ${_muscles.entries.where((entry) => _strong.contains(entry.key)).map((entry) => entry.value.toLowerCase()).join(', ')}',
        ].join(' · '),
        onEdit: () => _editFromReview(_focusStep),
      ),
    ];
  }

  Widget _review() {
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
              for (final (index, row) in _reviewRows().indexed) ...[
                if (index > 0) const Divider(height: TracendSpacing.xl),
                row,
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
        onReject: _confirmReject,
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
        const TracendLoader(size: 36, semanticLabel: 'Building your plan'),
        const SizedBox(height: TracendSpacing.lg),
        Text(
          'Building your plan',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Usually under a minute; it can take up to two. You can leave the app; your plan will be here when you come back.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  /// Shown once after approval, before the app opens.
  Widget _done(OnboardingProposal plan) {
    final text = Theme.of(context).textTheme;
    final today = DateTime.now().weekday;
    final ordered = [...plan.workouts]
      ..sort((a, b) => a.weekday.compareTo(b.weekday));
    final next = ordered.isEmpty
        ? null
        : ordered.firstWhere(
            (workout) => workout.weekday >= today,
            orElse: () => ordered.first,
          );
    final nextDay = next == null || next.weekday < 1 || next.weekday > 7
        ? ''
        : next.weekday == today
        ? 'Today'
        : onboardingWeekdayLabels[next.weekday - 1];
    final health = switch (_healthImport) {
      'connected' =>
        'Apple Health is connected. Today, your recovery and the Coach use it.',
      'empty' =>
        'Apple Health returned no data. Allow access in Settings, then refresh it in Account.',
      _ =>
        'Connect Apple Health any time in Account to add sleep, steps and workouts.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Set up Tracend')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          children: [
            _heading(
              "You're set.",
              'Your plan is active. Nothing else changes without your approval.',
            ),
            TracendCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.title, style: text.titleMedium),
                  if (next != null) ...[
                    const SizedBox(height: TracendSpacing.xs),
                    Text(
                      'Next session: $nextDay · ${next.name} · about ${next.estimatedMinutes} min',
                      style: text.bodyLarge,
                    ),
                  ],
                  const Divider(height: TracendSpacing.xl),
                  Text(
                    'Each day: ${plan.calories} kcal · ${plan.proteinG} g protein',
                    style: text.bodyLarge,
                  ),
                  const Divider(height: TracendSpacing.xl),
                  Text(health, style: text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.lg),
            FilledButton(
              onPressed: widget.onCompleted,
              child: const Text('Go to Today'),
            ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _note,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Example: fewer exercises per session, no deadlifts',
        ),
      ),
      const SizedBox(height: TracendSpacing.sm),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _note,
        builder: (context, value, _) => FilledButton(
          // Changes need words; an empty request would rebuild the same plan.
          onPressed: value.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(value.text.trim()),
          child: const Text('Request changes'),
        ),
      ),
    ],
  );
}

/// One answer among several, as a pressable card. The selected card carries
/// a lime ring, a lime wash and a filled check, so the state never rests on
/// colour alone.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
    this.icon,
    this.tag,
  });

  final bool selected;
  final IconData? icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  /// A short fact shown under the body, such as what Apple Health suggests.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(TracendRadii.card);
    return Semantics(
      container: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: TracendMotionScope.movement(context, TracendMotion.quick),
          decoration: BoxDecoration(
            color: selected ? colors.accentSignalTint : colors.surface,
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.accentSignalRing : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(TracendSpacing.md),
          child: Row(
            children: [
              if (icon != null) ...[
                TracendRowIcon(icon: icon!),
                const SizedBox(width: TracendSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(body, style: textTheme.bodyMedium),
                    if (tag != null)
                      Padding(
                        padding: const EdgeInsets.only(top: TracendSpacing.xxs),
                        child: Text(
                          tag!,
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.accentSignalInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              _CheckMark(checked: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round check used by choice cards and check rows: a filled lime disc
/// with a check when on, an empty ring when off.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: TracendMotionScope.movement(context, TracendMotion.quick),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? colors.accentSignal : Colors.transparent,
          border: checked
              ? null
              : Border.all(color: colors.textTertiary, width: 1.5),
        ),
        child: checked
            ? Icon(
                CupertinoIcons.checkmark_alt,
                size: 16,
                color: colors.onAccentSignal,
              )
            : null,
      ),
    );
  }
}

/// One answer from a few short options: a segmented control, or a list of
/// rows once large text would squeeze the segments.
class _SingleChoice<T extends Object> extends StatelessWidget {
  const _SingleChoice({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
      return Semantics(
        label: label,
        container: true,
        child: TracendSegmentedControl<Object>(
          segments: [for (final (value, text) in options) (value, text)],
          // An unanswered question selects no segment.
          selected: selected ?? const Object(),
          onChanged: (value) => onChanged(value as T),
        ),
      );
    }
    return TracendGroupedList(
      children: [
        for (final (value, text) in options)
          _CheckRow(
            title: text,
            checked: value == selected,
            exclusive: true,
            onChanged: (_) => onChanged(value),
          ),
      ],
    );
  }
}

/// A grouped-list row the athlete checks. The whole row is the target, and
/// VoiceOver reads it as a checkbox with its state.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.checked,
    required this.onChanged,
    this.exclusive = false,
  });

  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;

  /// One of a set where only one can be chosen (read as selected, not
  /// checked).
  final bool exclusive;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    checked: exclusive ? null : checked,
    selected: exclusive ? checked : null,
    inMutuallyExclusiveGroup: exclusive ? true : null,
    button: true,
    label: title,
    excludeSemantics: true,
    child: InkWell(
      onTap: () => onChanged(!checked),
      highlightColor: context.tracendColors.surfaceRaised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TracendListRow.minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              _CheckMark(checked: checked),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Onboarding progress as a thin segmented line: one segment per visible
/// step, done steps solid, the current step in lime. The step text above it
/// carries the meaning for VoiceOver.
class _StepLine extends StatelessWidget {
  const _StepLine({required this.count, required this.current});

  final int count;

  /// 1-based position of the current step.
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 1; i <= count; i++) ...[
            if (i > 1) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: TracendMotionScope.movement(
                  context,
                  TracendMotion.standard,
                ),
                height: 3,
                decoration: BoxDecoration(
                  color: i < current
                      ? colors.textPrimary
                      : i == current
                      ? colors.accentSignalRing
                      : colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(TracendRadii.pill),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, {required this.onEdit});

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: Theme.of(context).textTheme.labelMedium,
    );
    final edit = IconButton(
      tooltip: 'Edit ${label.toLowerCase()}',
      onPressed: onEdit,
      icon: const Icon(CupertinoIcons.pencil),
    );
    // Large text: the label sits above its value instead of a narrow column.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, Text(value)],
            ),
          ),
          edit,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: TracendSpacing.sm),
          child: SizedBox(width: 96, child: labelText),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.sm),
            child: Text(value),
          ),
        ),
        edit,
      ],
    );
  }
}

/// A slider with − and + buttons for exact values. The value is spoken with
/// its unit ("172 cm"), not as a percentage.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;

  void _nudge(double by) => onChanged(
    (((value + by) / step).round() * step).clamp(min, max).toDouble(),
  );

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Decrease ${label.toLowerCase()}',
        onPressed: value <= min ? null : () => _nudge(-step),
        icon: const Icon(CupertinoIcons.minus_circle),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          label: format(value),
          semanticFormatterCallback: format,
          onChanged: onChanged,
        ),
      ),
      IconButton(
        tooltip: 'Increase ${label.toLowerCase()}',
        onPressed: value >= max ? null : () => _nudge(step),
        icon: const Icon(CupertinoIcons.plus_circle),
      ),
    ],
  );
}

/// A reported barbell top set: the weight on the bar, the reps, and how many
/// more reps were left.
@immutable
class _LiftEntry {
  const _LiftEntry({
    required this.loadKg,
    required this.reps,
    required this.repsLeft,
  });

  static const initial = _LiftEntry(loadKg: 60, reps: 5, repsLeft: 2);

  factory _LiftEntry.fromJson(Map<dynamic, dynamic> json) => _LiftEntry(
    loadKg: (json['load_kg'] as num?)?.toDouble() ?? initial.loadKg,
    reps: (json['reps'] as num?)?.toInt() ?? initial.reps,
    repsLeft: (json['reps_left'] as num?)?.toInt() ?? initial.repsLeft,
  );

  final double loadKg;
  final int reps;
  final int repsLeft;

  _LiftEntry copyWith({double? loadKg, int? reps, int? repsLeft}) => _LiftEntry(
    loadKg: loadKg ?? this.loadKg,
    reps: reps ?? this.reps,
    repsLeft: repsLeft ?? this.repsLeft,
  );

  Map<String, Object> toJson(String slug) => {
    'slug': slug,
    'load_kg': loadKg,
    'reps': reps,
    'reps_left': repsLeft,
  };

  String get summary =>
      '${loadKg % 1 == 0 ? loadKg.toInt() : loadKg} kg × $reps'
      '${repsLeft == 0 ? ' to failure' : ', $repsLeft left'}';
}

class _LiftCard extends StatelessWidget {
  const _LiftCard({
    required this.name,
    required this.entry,
    required this.onChanged,
  });

  final String name;
  final _LiftEntry? entry;

  /// Null removes the lift.
  final ValueChanged<_LiftEntry?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lift = entry;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: lift != null,
            onChanged: (on) => onChanged(on ? _LiftEntry.initial : null),
            title: Text(name, style: text.titleMedium),
            subtitle: lift == null ? null : Text(lift.summary),
          ),
          if (lift != null) ...[
            Text('Weight on the bar: ${lift.summary.split(' ×').first}'),
            _Stepper(
              label: '$name weight',
              value: lift.loadKg.clamp(20, 400),
              min: 20,
              max: 400,
              step: 2.5,
              format: (value) => '${value % 1 == 0 ? value.toInt() : value} kg',
              onChanged: (value) => onChanged(lift.copyWith(loadKg: value)),
            ),
            Text('Reps: ${lift.reps}'),
            _Stepper(
              label: '$name reps',
              value: lift.reps.toDouble(),
              min: 1,
              max: 15,
              step: 1,
              format: (value) => '${value.round()} reps',
              onChanged: (value) =>
                  onChanged(lift.copyWith(reps: value.round())),
            ),
            const Text('Reps you could still have done'),
            const SizedBox(height: TracendSpacing.xs),
            Semantics(
              label: '$name reps you could still have done',
              container: true,
              child: TracendSegmentedControl<int>(
                segments: [
                  for (var left = 0; left <= 4; left++) (left, '$left'),
                ],
                selected: lift.repsLeft,
                onChanged: (left) => onChanged(lift.copyWith(repsLeft: left)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    required this.question,
    required this.answer,
    required this.onChanged,
  });

  final FollowUpQuestion question;
  final String answer;
  final ValueChanged<String> onChanged;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final _written = TextEditingController(
    text: widget.question.choices.contains(widget.answer) ? '' : widget.answer,
  );

  @override
  void dispose() {
    _written.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.question,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (question.choices.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.xs),
            Wrap(
              spacing: TracendSpacing.xs,
              runSpacing: TracendSpacing.xs,
              children: [
                for (final choice in question.choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: widget.answer == choice,
                    onSelected: (on) {
                      _written.clear();
                      widget.onChanged(on ? choice : '');
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: TracendSpacing.xs),
          TextField(
            controller: _written,
            minLines: 1,
            maxLines: 3,
            maxLength: 300,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: question.choices.isEmpty
                  ? 'Your answer'
                  : 'Or in your own words',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
