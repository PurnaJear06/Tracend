import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/widgets/coach_composer.dart';
import 'package:tracend/features/coach/widgets/coach_context_card.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/widgets/coach_thinking_indicator.dart';
import 'package:tracend/features/coach/widgets/preference_prompt_chip.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// A send that failed: what to say about it, the raw beta diagnostic, and
/// the question it was answering, which Retry asks again.
typedef _TurnFailure = ({String message, String? diagnostic, String question});

class CoachScreen extends StatefulWidget {
  const CoachScreen({
    this.repository = const FixtureCoachRepository(),
    this.threadMemory = const SharedPreferencesCoachThreadMemory(),
    this.aiConsent,
    super.key,
  });
  final CoachRepository repository;
  final CoachThreadMemory threadMemory;

  /// Chat and decisions send the athlete's data to the AI provider only while
  /// this is granted. Null without a backend, where nothing is sent.
  final AiCoachingConsentController? aiConsent;
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Future<List<CoachContextSource>>? _contextStatus;
  CoachChatRepository? get _chat => widget.repository is CoachChatRepository
      ? widget.repository as CoachChatRepository
      : null;

  /// Saved conversations. A notifier, so an open thread sheet follows
  /// refreshes and deletes.
  final _threadList = ValueNotifier<List<CoachThread>>(const []);
  List<CoachThread> get _threads => _threadList.value;
  set _threads(List<CoachThread> value) => _threadList.value = value;
  List<CoachMessage> _messages = const [];

  /// Null while the user is on a new conversation: its server thread is
  /// created by the first send, so opening Coach never leaves an empty thread.
  String? _threadId;

  /// Changes whenever the user switches conversations (New or opening one).
  /// A send finishes only in the conversation it started in: if the user has
  /// moved on, its new thread is not selected and its reply is not shown
  /// there. The server still keeps both, so the thread appears in the list.
  int _view = 0;

  /// Only the newest thread-list request may replace the list.
  int _threadsRequest = 0;

  /// Bumped when a failed delete puts a swiped row back, so the row is built
  /// fresh rather than as the dismissed one.
  int _restoredRows = 0;
  bool _loadingChat = true;
  bool _sending = false;

  /// A problem with the conversations themselves (loading, deleting).
  String? _error;

  /// The last send failed; shown under its question.
  _TurnFailure? _turnFailure;
  Map<String, dynamic>? _preferencePrompt;
  StreamSubscription<int>? _cooldownSubscription;
  int? _cooldownRemaining;

  bool get _aiAllowed => widget.aiConsent?.granted ?? true;

  void _consentChanged() => setState(() {});

  Future<void> _reviewAiCoaching() =>
      showAiCoachingConsentSheet(context, widget.aiConsent!);

  @override
  void initState() {
    super.initState();
    widget.aiConsent?.addListener(_consentChanged);
    if (widget.repository is CoachContextRepository) {
      _contextStatus = (widget.repository as CoachContextRepository)
          .loadContextStatus();
    }
    _restoreChat();
  }

  @override
  void didUpdateWidget(CoachScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiConsent != widget.aiConsent) {
      oldWidget.aiConsent?.removeListener(_consentChanged);
      widget.aiConsent?.addListener(_consentChanged);
    }
  }

  @override
  void dispose() {
    widget.aiConsent?.removeListener(_consentChanged);
    _composer.dispose();
    _scroll.dispose();
    _threadList.dispose();
    _cooldownSubscription?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownSubscription?.cancel();
    final stream = Stream.periodic(
      const Duration(seconds: 1),
      (tick) => seconds - tick - 1,
    ).take(seconds);
    setState(() => _cooldownRemaining = seconds);
    _cooldownSubscription = stream.listen(
      (remaining) {
        if (!mounted) return;
        setState(() => _cooldownRemaining = remaining);
      },
      onDone: () {
        if (mounted) setState(() => _cooldownRemaining = null);
      },
    );
  }

  Future<void> _restoreChat() async {
    final chat = _chat;
    if (chat == null) {
      if (mounted) setState(() => _loadingChat = false);
      return;
    }
    try {
      final (threads, remembered) = await (
        chat.loadThreads(),
        widget.threadMemory.lastThreadId(),
      ).wait;
      // Reopen the conversation the user last had open; otherwise the one
      // with the newest message; with none, start a new conversation.
      final threadId = threads.any((thread) => thread.id == remembered)
          ? remembered
          : threads.firstOrNull?.id;
      final messages = threadId == null
          ? const <CoachMessage>[]
          : await chat.loadMessages(threadId);
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _threadId = threadId;
        _messages = messages;
        _loadingChat = false;
      });
      _scrollToEnd(animate: false);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _error = 'Saved conversations could not be loaded.';
        });
      }
    }
  }

  Future<void> _openThread(String id) async {
    final chat = _chat;
    if (chat == null) return;
    setState(() {
      _view++;
      _loadingChat = true;
      _threadId = id;
      _error = null;
      _turnFailure = null;
      _preferencePrompt = null;
    });
    unawaited(widget.threadMemory.remember(id));
    try {
      final messages = await chat.loadMessages(id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _loadingChat = false;
        });
        _scrollToEnd(animate: false);
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _error = 'Conversation could not be opened.';
        });
      }
    }
  }

  void _newThread() => setState(() {
    _view++;
    _threadId = null;
    _messages = const [];
    _error = null;
    _turnFailure = null;
    _preferencePrompt = null;
  });

  /// Creates the server thread for a new conversation's first send. It is
  /// selected and listed (under its first question, the title the server
  /// gives it) only if the user is still on that conversation.
  Future<String> _startThread(
    CoachChatRepository chat,
    int view,
    String question,
  ) async {
    final id = await chat.createThread();
    if (mounted && _view == view) {
      unawaited(widget.threadMemory.remember(id));
      setState(() {
        _threadId = id;
        // A list requested before this thread existed would drop it, so it
        // no longer applies; this send's own refresh brings the server list.
        _threadsRequest++;
        _threads = [
          CoachThread(id: id, title: question, updatedAt: DateTime.now()),
          ..._threads,
        ];
      });
    }
    return id;
  }

  /// The server saves each question when its turn starts and names a new
  /// thread after its first question, so the list changes after every send,
  /// whether or not the Coach answered.
  Future<void> _refreshThreads(CoachChatRepository chat) async {
    final request = ++_threadsRequest;
    try {
      final threads = await chat.loadThreads();
      if (mounted && request == _threadsRequest) {
        setState(() => _threads = threads);
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }

  Future<void> _send([String? suggestion]) async {
    final chat = _chat;
    final question = (suggestion ?? _composer.text).trim();
    if (chat == null || question.isEmpty || _sending || _loadingChat) {
      return;
    }
    if (!_aiAllowed) {
      await _reviewAiCoaching();
      return;
    }
    unawaited(TracendHaptics.light());
    // Retry and suggestion chips keep whatever the user is typing.
    if (suggestion == null) _composer.clear();
    final view = _view;
    final local = CoachMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: question,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, local];
      _sending = true;
      _turnFailure = null;
      _preferencePrompt = null;
    });
    _scrollToEnd();
    final started = DateTime.now();
    try {
      final threadId = _threadId ?? await _startThread(chat, view, question);
      // AI coaching can be turned off in Account while the thread is
      // created; nothing is sent to the provider after that.
      if (!_aiAllowed) {
        if (mounted) {
          if (suggestion == null && _composer.text.isEmpty) {
            _composer.text = question;
          }
          setState(() {
            _messages = [
              for (final message in _messages)
                if (message.id != local.id) message,
            ];
            _sending = false;
          });
        }
        unawaited(_refreshThreads(chat));
        return;
      }
      final answer = await chat.sendMessage(threadId, question);
      Map<String, dynamic>? prompt;
      if (chat is SupabaseCoachRepository) {
        final raw = await chat.loadLastRawResponse();
        if (raw != null && raw['preference_prompt'] is Map) {
          prompt = Map<String, dynamic>.from(raw['preference_prompt'] as Map);
        }
      }
      final elapsed = DateTime.now().difference(started);
      if (chat is SupabaseCoachRepository &&
          elapsed < const Duration(milliseconds: 1200)) {
        await Future.delayed(const Duration(milliseconds: 1200) - elapsed);
      }
      if (mounted) {
        unawaited(TracendHaptics.light());
        setState(() {
          if (_view == view) {
            _messages = [..._messages, answer];
            _preferencePrompt = prompt;
          }
          _sending = false;
        });
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) {
        if (e is CoachUnavailableException) {
          final retrySec = e.retryAfterSeconds;
          if (retrySec != null && retrySec > 0) _startCooldown(retrySec);
        }
        final elapsed = DateTime.now().difference(started);
        if (chat is SupabaseCoachRepository &&
            elapsed < const Duration(milliseconds: 1200)) {
          await Future.delayed(const Duration(milliseconds: 1200) - elapsed);
          if (!mounted) return;
        }
        final failure = _describeFailure(e, question);
        setState(() {
          _sending = false;
          if (_view == view) _turnFailure = failure;
        });
        TracendToast.show(
          context,
          'Coach couldn’t answer',
          icon: CupertinoIcons.exclamationmark_circle,
        );
        _scrollToEnd();
      }
    }
    unawaited(_refreshThreads(chat));
  }

  /// What to say about a failed send, in plain words, with the raw text as
  /// the beta diagnostic. During the private beta the raw text stays visible
  /// (with its HTTP status and the server's stable code) so the owner can
  /// see where a failure comes from (owner decision, 2026-09-27).
  _TurnFailure _describeFailure(Object error, String question) {
    String raw(Object value) => value
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Bad state: ', '');
    return switch (error) {
      TimeoutException() => (
        message: 'Coach took too long to respond. Please try again.',
        diagnostic: 'Beta diagnostic: ${raw(error)}',
        question: question,
      ),
      CoachUnavailableException(:final message, :final code) => (
        message: message,
        diagnostic: code == null ? null : 'Beta diagnostic: $code',
        question: question,
      ),
      _ => (
        message: 'Coach couldn’t answer. Your approved plan is unchanged.',
        diagnostic: raw(error),
        question: question,
      ),
    };
  }

  /// Retry is offered on a data summary that ends the conversation. It asks
  /// the question the summary answered again, as a new turn with a new key.
  VoidCallback? _retryFor(int index) {
    if (index != _messages.length - 1 || _sending) return null;
    for (var i = index - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        final question = _messages[i].content;
        return () => _send(question);
      }
    }
    return null;
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        unawaited(
          _scroll.animateTo(
            end,
            duration: TracendMotion.standard,
            curve: TracendMotion.curve,
          ),
        );
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  Future<void> _savePreference(Map<String, dynamic> prompt) async {
    setState(() => _preferencePrompt = null);
    final chat = _chat;
    if (chat is! SupabaseCoachRepository) return;
    try {
      await chat.confirmPreference(
        category: prompt['category'] as String? ?? 'food',
        key: prompt['key'] as String? ?? '',
        value: prompt['value'] as String? ?? '',
        provenance: prompt['provenance'] as String? ?? 'chat_statement',
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() => _error = 'The preference could not be saved.');
      }
    }
  }

  Future<bool> _confirmDelete() => showTracendConfirm(
    context,
    title: 'Delete this conversation?',
    message:
        'Its messages are deleted for good. Your plan and logged data stay '
        'as they are.',
    confirmLabel: 'Delete conversation',
    destructive: true,
  );

  /// Removes [thread] from the list at once (a swiped row has already left),
  /// then deletes it on the server. Deleting the open conversation starts a
  /// new one. A failed delete puts the row back and says so.
  Future<void> _deleteThread(CoachThread thread) async {
    final chat = _chat;
    if (chat == null) return;
    final before = _threads;
    setState(() {
      _threadsRequest++;
      _threads = [
        for (final item in _threads)
          if (item.id != thread.id) item,
      ];
    });
    if (_threadId == thread.id) _newThread();
    try {
      await chat.deleteThread(thread.id);
      if (mounted) {
        TracendToast.show(
          context,
          'Conversation deleted',
          icon: CupertinoIcons.trash,
        );
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted) return;
      setState(() {
        _threadsRequest++;
        _restoredRows++;
        _threads = before;
        _error = 'The conversation could not be deleted.';
      });
      TracendToast.show(
        context,
        'Couldn’t delete the conversation',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  void _showThreads() => showTracendSheet<void>(
    context,
    title: 'Saved conversations',
    subtitle: _threads.isEmpty
        ? null
        : 'Swipe left on a conversation to delete it.',
    builder: (sheetContext) => ValueListenableBuilder<List<CoachThread>>(
      valueListenable: _threadList,
      builder: (context, threads, _) => Padding(
        padding: const EdgeInsets.only(bottom: TracendSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _newThread();
              },
              icon: const Icon(CupertinoIcons.square_pencil, size: 20),
              label: const Text('New conversation'),
            ),
            const SizedBox(height: TracendSpacing.md),
            if (threads.isEmpty)
              Text(
                'A conversation is saved here after its first message.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.tracendColors.textSecondary,
                ),
              )
            else
              TracendGroupedList(
                children: [
                  for (final thread in threads)
                    _ThreadRow(
                      key: ValueKey('${thread.id}-$_restoredRows'),
                      thread: thread,
                      open: thread.id == _threadId,
                      onOpen: () {
                        Navigator.pop(sheetContext);
                        if (thread.id != _threadId) _openThread(thread.id);
                      },
                      confirmDelete: _confirmDelete,
                      onDelete: () => _deleteThread(thread),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              // Dragging the conversation puts the keyboard away.
              onNotification: (notification) {
                if (notification.dragDetails != null) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: PrimaryScrollController(
                controller: _scroll,
                child: TracendScrollView(
                  title: 'Coach',
                  children: _content(context),
                ),
              ),
            ),
          ),
          // The threads button stays pinned where the inline title bar
          // appears, as an iOS bar button does, so it is in reach at the end
          // of a long conversation without scrolling back up.
          Positioned(
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: MediaQuery.sizeOf(context).width < 375
                          ? TracendSpacing.md
                          : TracendSpacing.gutter,
                    ),
                    child: IconButton.filled(
                      tooltip: 'Saved conversations',
                      onPressed: _chat == null ? null : _showThreads,
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surface,
                        foregroundColor: colors.textPrimary,
                        disabledBackgroundColor: colors.surface,
                        minimumSize: const Size.square(44),
                        fixedSize: const Size.square(44),
                      ),
                      icon: const Icon(CupertinoIcons.chat_bubble_2, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CoachComposer(
              controller: _composer,
              enabled:
                  _aiAllowed &&
                  !_sending &&
                  !_loadingChat &&
                  _chat != null &&
                  _cooldownRemaining == null,
              cooldownRemaining: _cooldownRemaining,
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final failure = _turnFailure;
    final prompt = _preferencePrompt;
    return [
      if (_error != null) ...[
        _Notice(_error!),
        const SizedBox(height: TracendSpacing.md),
      ],
      if (!_aiAllowed) ...[
        TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI coaching is off', style: textTheme.titleMedium),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                'The Coach sends your Tracend data to '
                '${widget.aiConsent!.notice.providerLabel} to answer, so it '
                'needs your permission first.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: TracendSpacing.sm),
              OutlinedButton(
                onPressed: _reviewAiCoaching,
                child: const Text('Review AI coaching'),
              ),
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.lg),
      ],
      if (_loadingChat)
        const _ConversationSkeleton()
      else if (_messages.isEmpty) ...[
        Text(
          'Ask about training, meals, recovery, progress, evidence, or how to '
          'use Tracend. The Coach cannot silently change your plan or '
          'confirmed data.',
          style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.md),
        // What the Coach can see, shown once on a new conversation rather
        // than above every one. Today's decision lives on Today.
        if (_contextStatus != null) ...[
          FutureBuilder<List<CoachContextSource>>(
            future: _contextStatus,
            builder: (context, snapshot) => CoachContextCard(
              sources: snapshot.data,
              loading: snapshot.connectionState == ConnectionState.waiting,
            ),
          ),
          const SizedBox(height: TracendSpacing.lg),
        ],
        // Padded chips already keep 8pt between rows.
        Wrap(
          spacing: TracendSpacing.xs,
          children: [
            for (final suggestion in const [
              'What should I do next?',
              'Explain today’s evidence',
              'What is my next meal?',
            ])
              ActionChip(
                label: Text(suggestion),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => _send(suggestion),
              ),
          ],
        ),
      ] else
        for (final (index, message) in _messages.indexed) ...[
          if (index > 0)
            SizedBox(
              height: message.role == 'user'
                  ? TracendSpacing.xl
                  : TracendSpacing.md,
            ),
          CoachMessageBubble(
            message: message,
            onSendFollowUp: (suggestion) => _send(suggestion),
            onRetry: message.isDataSummary ? _retryFor(index) : null,
          ),
        ],
      if (failure != null && !_loadingChat) ...[
        const SizedBox(height: TracendSpacing.md),
        CoachTurnError(
          message: failure.message,
          diagnostic: failure.diagnostic,
          onRetry: _sending || _cooldownRemaining != null
              ? null
              : () => _send(failure.question),
        ),
      ],
      if (_sending) ...[
        const SizedBox(height: TracendSpacing.md),
        const Align(
          alignment: Alignment.centerLeft,
          child: CoachThinkingIndicator(),
        ),
      ],
      if (prompt != null) ...[
        const SizedBox(height: TracendSpacing.lg),
        PreferencePromptChip(
          category: prompt['category'] as String? ?? 'food',
          prefKey: prompt['key'] as String? ?? '',
          value: prompt['value'] as String? ?? '',
          onConfirm: () => _savePreference(prompt),
          onDismiss: () => setState(() => _preferencePrompt = null),
        ),
      ],
    ];
  }
}

/// One saved conversation in the thread sheet. Swiping it left asks before
/// deleting; VoiceOver offers the same delete as a custom action.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.open,
    required this.onOpen,
    required this.confirmDelete,
    required this.onDelete,
    super.key,
  });

  final CoachThread thread;
  final bool open;
  final VoidCallback onOpen;
  final Future<bool> Function() confirmDelete;
  final VoidCallback onDelete;

  /// Thread titles are the first question, which can be long.
  static String _title(String title) {
    final flat = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 80) return flat;
    final cut = flat.substring(0, 80);
    final space = cut.lastIndexOf(' ');
    return '${space > 40 ? cut.substring(0, space) : cut}…';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final updated = friendlyDate(thread.updatedAt.toLocal());
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete conversation'): () async {
          if (await confirmDelete()) onDelete();
        },
      },
      child: Dismissible(
        key: ValueKey('dismiss-${thread.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => confirmDelete(),
        onDismissed: (_) => onDelete(),
        // The canvas tone reads on the danger fill in both themes (dark ink
        // on the light coral, light ink on the deep red).
        background: ColoredBox(
          color: colors.stateDanger,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: TracendSpacing.gutter),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.trash, color: colors.canvas),
                  const SizedBox(width: TracendSpacing.xs),
                  Text(
                    'Delete',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: colors.canvas),
                  ),
                ],
              ),
            ),
          ),
        ),
        child: ColoredBox(
          color: colors.surface,
          child: TracendListRow(
            title: _title(thread.title),
            subtitle: open ? 'Open now · $updated' : updated,
            onTap: onOpen,
          ),
        ),
      ),
    );
  }
}

/// A quiet line about a problem with the conversations themselves.
class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 18,
              color: colors.stateAttention,
            ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A question and a reply in outline while a conversation loads.
class _ConversationSkeleton extends StatelessWidget {
  const _ConversationSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading conversation',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FractionallySizedBox(
          widthFactor: 0.6,
          child: TracendSkeleton.block(height: 44, radius: 18),
        ),
        SizedBox(height: TracendSpacing.md),
        TracendSkeleton.line(),
        SizedBox(height: TracendSpacing.xs),
        TracendSkeleton.line(widthFactor: 0.9),
        SizedBox(height: TracendSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TracendSkeleton.line(widthFactor: 0.55),
        ),
      ],
    ),
  );
}
