import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Version of the AI coaching disclosure. Change it whenever the provider, the
/// data sent, or the purpose changes: a grant of an older version no longer
/// counts, so everyone is asked again.
const aiCoachingNoticeVersion = 'ai-coaching-v1';

/// The athlete's current answer to the AI coaching disclosure.
enum AiCoachingChoice { undecided, granted, declined }

/// Reads the newest `ai_coaching` record (or none). Only a grant of the
/// current notice version counts as granted.
AiCoachingChoice aiCoachingChoiceFrom(Map<String, dynamic>? latest) {
  if (latest == null) return AiCoachingChoice.undecided;
  if (latest['action'] != 'granted') return AiCoachingChoice.declined;
  return latest['notice_version'] == aiCoachingNoticeVersion
      ? AiCoachingChoice.granted
      : AiCoachingChoice.undecided;
}

abstract interface class AiCoachingConsentRepository {
  /// The newest `ai_coaching` record: a grant of the current notice version,
  /// a decline, or none (also when the grant was of an older version).
  Future<AiCoachingChoice> load();

  /// Appends a grant, or a decline stored as `withdrawn`.
  Future<void> record({required bool granted});
}

class SupabaseAiCoachingConsentRepository
    implements AiCoachingConsentRepository {
  SupabaseAiCoachingConsentRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AiCoachingChoice> load() async {
    final rows = await _client
        .from('consent_records')
        .select('notice_version,action')
        .eq('consent_type', 'ai_coaching')
        .order('created_at', ascending: false)
        .limit(1);
    return aiCoachingChoiceFrom(rows.isEmpty ? null : rows.first);
  }

  @override
  Future<void> record({required bool granted}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'ai_coaching',
      'notice_version': aiCoachingNoticeVersion,
      'action': granted ? 'granted' : 'withdrawn',
      'source': 'ios_app',
    });
  }
}

/// In-memory choice for builds without a backend and for tests.
class FixtureAiCoachingConsentRepository
    implements AiCoachingConsentRepository {
  FixtureAiCoachingConsentRepository([
    this.choice = AiCoachingChoice.undecided,
  ]);

  AiCoachingChoice choice;
  final recorded = <bool>[];

  @override
  Future<AiCoachingChoice> load() async => choice;

  @override
  Future<void> record({required bool granted}) async {
    recorded.add(granted);
    choice = granted ? AiCoachingChoice.granted : AiCoachingChoice.declined;
  }
}

/// The signed-in athlete's AI coaching choice, shared by the screens that
/// send data to the AI provider.
class AiCoachingConsentController extends ChangeNotifier {
  AiCoachingConsentController(
    this._repository, {
    AiCoachingChoice initial = AiCoachingChoice.undecided,
  }) : _choice = initial;

  final AiCoachingConsentRepository _repository;
  AiCoachingChoice _choice;

  AiCoachingChoice get choice => _choice;
  bool get granted => _choice == AiCoachingChoice.granted;

  Future<void> load() async {
    _choice = await _repository.load();
    notifyListeners();
  }

  Future<void> record({required bool granted}) async {
    await _repository.record(granted: granted);
    _choice = granted ? AiCoachingChoice.granted : AiCoachingChoice.declined;
    notifyListeners();
  }
}

/// What AI coaching sends, to whom, and what still works without it.
class AiCoachingDisclosure extends StatelessWidget {
  const AiCoachingDisclosure({super.key});

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The Coach chat and your daily decision are written by an AI model. '
          'To write them, Tracend sends DeepSeek your training plan and '
          'workout logs, check-ins, Apple Health summaries (sleep, heart rate, '
          'HRV, steps and workouts), meals and nutrition targets, body '
          'measurements, goals and preferences, and the messages you send the '
          'Coach. Your name, email address and photos are not sent.',
          style: body,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., '
          'Ltd. and processes this data on servers in China. Its terms, not '
          'Tracend’s, decide how long it keeps requests.',
          style: body,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'Without AI coaching, your plan, logging, Apple Health sync and '
          'progress keep working; the Coach chat and AI daily decisions stay '
          'off. You can change this at any time in Account.',
          style: body,
        ),
      ],
    );
  }
}

/// Full-screen question for an athlete who has not answered yet: shown once
/// after onboarding, for accounts created before the question existed, and
/// again whenever the notice version changes.
class AiCoachingConsentScreen extends StatefulWidget {
  const AiCoachingConsentScreen({
    required this.controller,
    required this.onDecided,
    super.key,
  });

  final AiCoachingConsentController controller;
  final VoidCallback onDecided;

  @override
  State<AiCoachingConsentScreen> createState() =>
      _AiCoachingConsentScreenState();
}

class _AiCoachingConsentScreenState extends State<AiCoachingConsentScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _decide(bool granted) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.record(granted: granted);
      widget.onDecided();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Your choice was not saved. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI coaching')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(TracendSpacing.gutter),
        children: [
          Text(
            'Allow AI coaching?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          const AiCoachingDisclosure(),
          const SizedBox(height: TracendSpacing.lg),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          AiCoachingConsentButtons(saving: _saving, onDecide: _decide),
        ],
      ),
    ),
  );
}

/// "Allow AI coaching" and "Not now", shared by every place that asks.
class AiCoachingConsentButtons extends StatelessWidget {
  const AiCoachingConsentButtons({
    required this.saving,
    required this.onDecide,
    super.key,
  });

  final bool saving;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: saving ? null : () => onDecide(true),
        icon: const Icon(CupertinoIcons.sparkles),
        label: const Text('Allow AI coaching'),
      ),
      const SizedBox(height: TracendSpacing.xs),
      TextButton(
        onPressed: saving ? null : () => onDecide(false),
        child: const Text('Not now'),
      ),
    ],
  );
}

/// Opens the disclosure as a sheet from Coach or Account.
Future<void> showAiCoachingConsentSheet(
  BuildContext context,
  AiCoachingConsentController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => _AiCoachingConsentSheet(controller: controller),
);

class _AiCoachingConsentSheet extends StatefulWidget {
  const _AiCoachingConsentSheet({required this.controller});

  final AiCoachingConsentController controller;

  @override
  State<_AiCoachingConsentSheet> createState() =>
      _AiCoachingConsentSheetState();
}

class _AiCoachingConsentSheetState extends State<_AiCoachingConsentSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _decide(bool granted) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.record(granted: granted);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Your choice was not saved. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(TracendSpacing.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AI coaching is ${widget.controller.granted ? 'on' : 'off'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: TracendSpacing.md),
        const AiCoachingDisclosure(),
        const SizedBox(height: TracendSpacing.lg),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: context.tracendColors.stateDanger),
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
        if (widget.controller.granted) ...[
          OutlinedButton(
            onPressed: _saving ? null : () => _decide(false),
            child: const Text('Turn off AI coaching'),
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it on'),
          ),
        ] else
          AiCoachingConsentButtons(saving: _saving, onDecide: _decide),
      ],
    ),
  );
}
