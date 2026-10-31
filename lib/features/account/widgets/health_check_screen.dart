import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';
import 'package:tracend/features/onboarding/screening_form.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';

/// Reopens the health check after onboarding. The athlete's own updated
/// answers are the only way a limit on the plan's effort lifts: the server
/// works out the outcome from them, and a professional's clearance counts
/// only as the athlete states it. This is not a medical check.
class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({required this.repository, super.key});

  final ScreeningRepository repository;

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;
  bool _saved = false;

  bool? _exercisesRegularly;
  bool? _knownCondition;
  bool? _symptoms;
  bool? _clearedByProfessional;

  /// What the server holds for the answers on screen; null once they change.
  ScreeningOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final stored = await widget.repository.loadScreening();
      if (!mounted) return;
      final answers = stored.answers;
      setState(() {
        _exercisesRegularly = answers?.exercisesRegularly;
        _knownCondition = answers?.knownCondition;
        _symptoms = answers?.symptoms;
        _clearedByProfessional = answers?.clearedByProfessional;
        _outcome = answers == null ? null : stored.outcome;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  ScreeningAnswers? get _answers => ScreeningAnswers.fromChoices(
    exercisesRegularly: _exercisesRegularly,
    knownCondition: _knownCondition,
    symptoms: _symptoms,
    clearedByProfessional: _clearedByProfessional,
  );

  void _answer(VoidCallback change) {
    if (_saving) return;
    setState(() {
      change();
      _outcome = null;
      _saved = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    final submitted = _answers;
    if (submitted == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.repository.recordScreening(submitted);
      if (!mounted) return;
      setState(() {
        _outcome = record.outcome;
        _saved = true;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Your answers were not saved. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? get _savedNote => !_saved
      ? null
      : _outcome == ScreeningOutcome.cleared
      ? 'Saved. Your answers set no limit on your plan. A plan you already have keeps its effort until it is next changed.'
      : 'Saved.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    return Scaffold(
      appBar: AppBar(title: const Text('Health check')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(
                child: TracendLoader(semanticLabel: 'Loading your answers'),
              )
            : _loadFailed
            ? AccountDetailMessage(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'Your answers could not load',
                detail:
                    'Nothing was changed. Check the connection and try again.',
                action: FilledButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  TracendSpacing.xs,
                  gutter,
                  TracendSpacing.xxl,
                ),
                children: [
                  Text(
                    'Update your health check.',
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  Text(
                    'Four short questions that set how hard your plan may ask you to work. Only your own answers change this. This is not a medical check and Tracend does not diagnose anything.',
                    style: textTheme.bodyLarge,
                  ),
                  ScreeningForm(
                    exercisesRegularly: _exercisesRegularly,
                    knownCondition: _knownCondition,
                    symptoms: _symptoms,
                    clearedByProfessional: _clearedByProfessional,
                    outcome: _outcome,
                    locked: _saving,
                    onExercisesRegularly: (value) =>
                        _answer(() => _exercisesRegularly = value),
                    onKnownCondition: (value) =>
                        _answer(() => _knownCondition = value),
                    onSymptoms: (value) => _answer(() => _symptoms = value),
                    onClearedByProfessional: (value) =>
                        _answer(() => _clearedByProfessional = value),
                  ),
                  const SizedBox(height: TracendSpacing.lg),
                  if (_error case final message?) _Note(message, danger: true),
                  if (_savedNote case final note?) _Note(note),
                  FilledButton(
                    onPressed: _answers == null || _saving ? null : _save,
                    child: _saving
                        ? const TracendLoader(size: 24, semanticLabel: 'Saving')
                        : const Text('Save answers'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: danger ? context.tracendColors.stateDanger : null,
        ),
      ),
    ),
  );
}
