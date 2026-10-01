import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Version of the built-in AI coaching disclosure, shown only when the
/// server's current notice cannot be loaded. The notice the athlete answers is
/// server data (`get_current_ai_notice`): the owner republishes it when the
/// provider, the data sent or the purpose changes, and a grant of an older
/// version no longer counts, so everyone is asked again.
const aiCoachingNoticeVersion = 'ai-coaching-v1';

/// An AI notice: what AI coaching sends, to whom, and what works without it.
class AiNotice {
  const AiNotice({
    required this.version,
    required this.providerLabel,
    required this.body,
  });

  final String version;
  final String providerLabel;

  /// Paragraphs separated by blank lines.
  final String body;

  /// The notice built into this app, matching `ai-coaching-v1` on the server.
  static const builtIn = AiNotice(
    version: aiCoachingNoticeVersion,
    providerLabel: 'DeepSeek',
    body:
        'The Coach chat and your daily decision are written by an AI model. '
        'To write them, Tracend sends DeepSeek your training plan and '
        'workout logs, check-ins, Apple Health summaries (sleep, heart rate, '
        'HRV, steps and workouts), meals and nutrition targets, body '
        'measurements, goals and preferences, and the messages you send the '
        'Coach. Your name, email address and photos are not sent.\n\n'
        'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., '
        'Ltd. and processes this data on servers in China. Its terms, not '
        'Tracend’s, decide how long it keeps requests.\n\n'
        'Without AI coaching, your plan, logging, Apple Health sync and '
        'progress keep working; the Coach chat and AI daily decisions stay '
        'off. You can change this at any time in Account.',
  );

  /// Reads `get_current_ai_notice`; null when the response is not a notice.
  static AiNotice? fromJson(Object? value) {
    if (value is! Map) return null;
    final version = value['version'];
    final provider = value['provider_label'];
    final body = value['body'];
    if (version is! String || provider is! String || body is! String) {
      return null;
    }
    if (version.isEmpty || body.trim().isEmpty) return null;
    return AiNotice(version: version, providerLabel: provider, body: body);
  }

  List<String> get paragraphs => body
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
}

/// The athlete's current answer to the AI coaching disclosure.
enum AiCoachingChoice { undecided, granted, declined }

/// Reads the newest `ai_coaching` record (or none). Only a grant of the
/// current notice version counts as granted.
AiCoachingChoice aiCoachingChoiceFrom(
  Map<String, dynamic>? latest, {
  String currentVersion = aiCoachingNoticeVersion,
}) {
  if (latest == null) return AiCoachingChoice.undecided;
  if (latest['action'] != 'granted') return AiCoachingChoice.declined;
  return latest['notice_version'] == currentVersion
      ? AiCoachingChoice.granted
      : AiCoachingChoice.undecided;
}

abstract interface class AiCoachingConsentRepository {
  /// The notice the athlete is asked about, as of the last [load].
  AiNotice get notice;

  /// Loads the current notice, then the newest `ai_coaching` record: a grant
  /// of that notice, a decline, or none (also when the grant was of an older
  /// version).
  Future<AiCoachingChoice> load();

  /// Appends a grant, or a decline stored as `withdrawn`.
  Future<void> record({required bool granted});
}

class SupabaseAiCoachingConsentRepository
    implements AiCoachingConsentRepository {
  SupabaseAiCoachingConsentRepository(this._client);

  final SupabaseClient _client;

  @override
  AiNotice notice = AiNotice.builtIn;

  @override
  Future<AiCoachingChoice> load() async {
    try {
      notice =
          AiNotice.fromJson(await _client.rpc('get_current_ai_notice')) ??
          AiNotice.builtIn;
    } catch (e) {
      // Builds older than the server notice, or an offline moment, keep the
      // built-in text; the server still decides what a grant covers.
      debugPrint('Non-critical error: $e');
      notice = AiNotice.builtIn;
    }
    final rows = await _client
        .from('consent_records')
        .select('notice_version,action')
        .eq('consent_type', 'ai_coaching')
        .order('created_at', ascending: false)
        .limit(1);
    return aiCoachingChoiceFrom(
      rows.isEmpty ? null : rows.first,
      currentVersion: notice.version,
    );
  }

  @override
  Future<void> record({required bool granted}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'ai_coaching',
      'notice_version': notice.version,
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
    this.notice = AiNotice.builtIn,
  ]);

  AiCoachingChoice choice;

  @override
  AiNotice notice;
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

  /// The notice the athlete answers; recorded with their choice.
  AiNotice get notice => _repository.notice;

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

/// What AI coaching sends, to whom, and what still works without it: the
/// current server notice, or the built-in one.
class AiCoachingDisclosure extends StatelessWidget {
  const AiCoachingDisclosure({this.notice = AiNotice.builtIn, super.key});

  final AiNotice notice;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final paragraphs = notice.paragraphs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: TracendSpacing.sm),
          Text(paragraphs[i], style: body),
        ],
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
          AiCoachingDisclosure(notice: widget.controller.notice),
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
        AiCoachingDisclosure(notice: widget.controller.notice),
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
