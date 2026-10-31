import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// The notice the athlete answers is server data (`get_current_ai_notice`):
/// the owner republishes it when the provider, the data sent or the purpose
/// changes, and a grant of an older version no longer counts, so everyone is
/// asked again. The app never shows a notice body it did not fetch and never
/// records an answer for a version it did not fetch. A notice that cannot be
/// loaded never blocks the signed-in app: AI coaching stays off, and only the
/// screens that ask about it show the error and a retry.
class AiNoticeUnavailable implements Exception {
  const AiNoticeUnavailable();

  @override
  String toString() => 'The AI coaching notice could not be loaded.';
}

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

  /// Reads a `get_current_ai_notice` response; null when it is not a notice.
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
  required String currentVersion,
}) {
  if (latest == null) return AiCoachingChoice.undecided;
  if (latest['action'] != 'granted') return AiCoachingChoice.declined;
  return latest['notice_version'] == currentVersion
      ? AiCoachingChoice.granted
      : AiCoachingChoice.undecided;
}

/// Fetches the server's current notice. A failed call or a response that is
/// not a notice is [AiNoticeUnavailable]: the app has no text of its own to
/// show in its place.
Future<AiNotice> loadCurrentAiNotice(Future<Object?> Function() fetch) async {
  final Object? response;
  try {
    response = await fetch();
  } catch (e) {
    logNonCritical(e);
    throw const AiNoticeUnavailable();
  }
  final notice = AiNotice.fromJson(response);
  if (notice == null) throw const AiNoticeUnavailable();
  return notice;
}

abstract interface class AiCoachingConsentRepository {
  /// The notice the athlete is asked about, as of the last [load]; null until
  /// one has loaded, and again after a load that failed.
  AiNotice? get notice;

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
  AiNotice? notice;

  @override
  Future<AiCoachingChoice> load() async {
    notice = null;
    final loaded = await loadCurrentAiNotice(
      () => _client.rpc('get_current_ai_notice'),
    );
    notice = loaded;
    final rows = await _client
        .from('consent_records')
        .select('notice_version,action')
        .eq('consent_type', 'ai_coaching')
        .order('created_at', ascending: false)
        .limit(1);
    return aiCoachingChoiceFrom(
      rows.isEmpty ? null : rows.first,
      currentVersion: loaded.version,
    );
  }

  @override
  Future<void> record({required bool granted}) async {
    final shown = notice;
    if (shown == null) throw const AiNoticeUnavailable();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'ai_coaching',
      'notice_version': shown.version,
      'action': granted ? 'granted' : 'withdrawn',
      'source': 'ios_app',
    });
  }
}

/// Neutral text for [FixtureAiCoachingConsentRepository]; it names no company.
const _fixtureNotice = AiNotice(
  version: 'fixture-notice-v1',
  providerLabel: 'Test',
  body:
      'This is a test notice. It stands in for the notice the server holds.\n\n'
      'Nothing is sent anywhere.\n\n'
      'You can change your answer at any time in Account.',
);

/// In-memory choice for tests. Pass a null notice to see the notice-unavailable
/// state.
class FixtureAiCoachingConsentRepository
    implements AiCoachingConsentRepository {
  FixtureAiCoachingConsentRepository([
    this.choice = AiCoachingChoice.undecided,
    this.notice = _fixtureNotice,
  ]);

  AiCoachingChoice choice;

  @override
  AiNotice? notice;
  final recorded = <bool>[];

  @override
  Future<AiCoachingChoice> load() async {
    if (notice == null) throw const AiNoticeUnavailable();
    return choice;
  }

  @override
  Future<void> record({required bool granted}) async {
    if (notice == null) throw const AiNoticeUnavailable();
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

  /// The notice the athlete answers, recorded with their choice; null while it
  /// has not loaded. [record] throws [AiNoticeUnavailable] rather than answer
  /// for a notice that was not fetched.
  AiNotice? get notice => _repository.notice;

  /// Loads the notice and the athlete's answer. A notice that cannot be
  /// loaded is not an error here: AI coaching is unavailable (off, with no
  /// answer assumed) until a later [load] succeeds. Other failures throw.
  Future<void> load() async {
    try {
      _choice = await _repository.load();
    } on AiNoticeUnavailable {
      _choice = AiCoachingChoice.undecided;
    }
    notifyListeners();
  }

  Future<void> record({required bool granted}) async {
    await _repository.record(granted: granted);
    _choice = granted ? AiCoachingChoice.granted : AiCoachingChoice.declined;
    notifyListeners();
  }
}

/// What AI coaching sends, to whom, and what still works without it: the
/// server's current notice.
class AiCoachingDisclosure extends StatelessWidget {
  const AiCoachingDisclosure({required this.notice, super.key});

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

/// The controller's notice, or the error and a retry when it has not loaded.
/// With no controller there is nothing to retry. The answer buttons belong
/// only under a loaded notice. [unavailableNote] says what happens meanwhile.
class AiCoachingNoticeSection extends StatefulWidget {
  const AiCoachingNoticeSection({
    this.controller,
    this.unavailableNote,
    super.key,
  });

  final AiCoachingConsentController? controller;
  final String? unavailableNote;

  @override
  State<AiCoachingNoticeSection> createState() =>
      _AiCoachingNoticeSectionState();
}

class _AiCoachingNoticeSectionState extends State<AiCoachingNoticeSection> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.controller!.load();
    } catch (e) {
      logNonCritical(e);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return const _NoticeUnavailable();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final notice = controller.notice;
        if (notice != null) return AiCoachingDisclosure(notice: notice);
        return _NoticeUnavailable(
          onRetry: _retrying ? null : _retry,
          note: widget.unavailableNote,
        );
      },
    );
  }
}

class _NoticeUnavailable extends StatelessWidget {
  const _NoticeUnavailable({this.onRetry, this.note});

  final VoidCallback? onRetry;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'The AI coaching notice could not be loaded. Check the connection '
        'and try again.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      if (note != null) ...[
        const SizedBox(height: TracendSpacing.xs),
        Text(note!, style: Theme.of(context).textTheme.bodyMedium),
      ],
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
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
      logNonCritical(e);
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
          AiCoachingNoticeSection(controller: widget.controller),
          const SizedBox(height: TracendSpacing.lg),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => widget.controller.notice == null
                ? const SizedBox.shrink()
                : AiCoachingConsentButtons(saving: _saving, onDecide: _decide),
          ),
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
) => showTracendSheet<void>(
  context,
  scrollable: false,
  padding: EdgeInsets.zero,
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
      logNonCritical(e);
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
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI coaching is ${widget.controller.granted ? 'on' : 'off'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TracendSpacing.md),
          AiCoachingNoticeSection(controller: widget.controller),
          const SizedBox(height: TracendSpacing.lg),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          if (widget.controller.notice == null)
            const SizedBox.shrink()
          else if (widget.controller.granted) ...[
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
    ),
  );
}
