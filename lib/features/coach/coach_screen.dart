import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
import 'package:tracend/features/coach/memory/fact_suggestion.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_card.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/coach/widgets/coach_composer.dart';
import 'package:tracend/features/coach/widgets/coach_context_card.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/widgets/coach_thinking_indicator.dart';
import 'package:tracend/features/coach/widgets/fact_suggestion_chip.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/coach_draft_requests.dart';
import 'package:tracend/shared/plan_changes.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';
import 'package:uuid/uuid.dart';

/// A send that failed: what to say about it, the raw beta diagnostic, the
/// question it was answering (which Retry asks again), the idempotency key
/// that attempt used, and what Retry may do. [reuseKey] says whether Retry
/// repeats that key (no answer reached the app, so the server may still
/// finish it); [replays] counts how many times the key has been repeated.
typedef _TurnFailure = ({
  String message,
  String? diagnostic,
  String question,
  String key,
  int replays,
  bool reuseKey,
  bool retryable,
  bool needsConsent,
});

/// A key is repeated at most this many times, so a turn the server lost
/// (it would answer "still working" forever) cannot trap Retry.
const _maxKeyReplays = 2;

/// Opening Coach reopens the last conversation only when its latest message is
/// newer than this. A day-old chat is a different topic: the athlete starts a
/// fresh one and can still continue the old one from the "Continue last chat"
/// row or Saved conversations.
const coachReopenWindow = Duration(hours: 6);

/// The screen's conversation as it was when the athlete started opening
/// another, so a failed open can put it back.
class _OpenedFrom {
  const _OpenedFrom({
    required this.view,
    required this.threadId,
    required this.previousThreadId,
    required this.remembered,
    required this.openedAt,
    required this.messages,
    required this.turnFailure,
    required this.factSuggestions,
    required this.budgetWarning,
  });

  final int view;
  final String? threadId;
  final String? previousThreadId;
  final bool remembered;
  final DateTime? openedAt;
  final List<CoachMessage> messages;
  final _TurnFailure? turnFailure;
  final List<CoachFactSuggestion> factSuggestions;
  final bool budgetWarning;
}

class CoachScreen extends StatefulWidget {
  const CoachScreen({
    this.repository = const FixtureCoachRepository(),
    this.threadMemory = const SharedPreferencesCoachThreadMemory(),
    this.aiConsent,
    this.proposals,
    this.planChanges,
    this.memory,
    this.draftRequests,
    this.now = DateTime.now,
    this.active = true,
    super.key,
  });
  final CoachRepository repository;

  /// Whether this is the visible tab. The shell keeps the screen alive while
  /// another tab shows, so becoming active again (like the app resuming)
  /// re-checks [coachReopenWindow] against the open conversation.
  final bool active;

  /// The clock behind [coachReopenWindow]; tests set it.
  final DateTime Function() now;
  final CoachThreadMemory threadMemory;

  /// Reads and answers the proposals Coach makes (A8). Null without a backend,
  /// where Coach makes none.
  final CoachProposalRepository? proposals;

  /// Saves what the athlete confirms when Coach suggests a fact. Null without a
  /// backend, where Coach suggests none.
  final CoachMemoryRepository? memory;

  /// Questions other screens leave for the composer ("Talk to Coach" on
  /// today's readiness card). The text is put in the box, never sent.
  final CoachDraftRequests? draftRequests;

  /// Announced when an approved or undone proposal changed the plan, the
  /// targets or the goal, so the screens that show them reload.
  final PlanChanges? planChanges;

  /// Chat and decisions send the athlete's data to the AI provider only while
  /// this is granted. Null without a backend, where nothing is sent.
  final AiCoachingConsentController? aiConsent;
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> with WidgetsBindingObserver {
  static const _uuid = Uuid();
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

  /// The choice on a new conversation: Coach does not remember it. Applied
  /// when the first send creates the thread, and fixed from then on.
  bool _rememberChat = true;

  /// Whether the open conversation is remembered. False shows the notice at
  /// the top of the conversation.
  bool _threadRemembered = true;

  /// Changes whenever the user switches conversations (New or opening one).
  /// A send finishes only in the conversation it started in: if the user has
  /// moved on, its new thread is not selected and its reply is not shown
  /// there. The server still keeps both, so the thread appears in the list.
  int _view = 0;
  int _viewSequence = 0;

  /// Starts a new view and returns its token. Tokens never repeat, so a
  /// request from a view that was left cannot match a later one.
  int _beginView() => _view = ++_viewSequence;

  /// What the screen showed before the conversation being opened, until that
  /// open settles. A failed open puts it back, so the messages on screen
  /// always belong to the thread id and its next send.
  _OpenedFrom? _openedFrom;

  /// A follow-up the athlete asked for (a chip, "Change it") while Coach was
  /// still answering or cooling down. It sends when Coach is free, and is
  /// shown meanwhile.
  String? _queuedFollowUp;

  /// When the athlete explicitly opened the current conversation (Continue
  /// last chat, Saved conversations). An old chat opened on purpose stays open
  /// for the visit: it counts as touched then, not at its last message.
  DateTime? _openedAt;

  /// The conversation a fresh view replaced, offered as "Continue last chat".
  /// Null falls back to the newest saved conversation.
  String? _previousThreadId;

  /// Only the newest thread-list request may replace the list.
  int _threadsRequest = 0;

  /// Bumped when a failed delete puts a swiped row back, so the row is built
  /// fresh rather than as the dismissed one.
  int _restoredRows = 0;
  bool _loadingChat = true;
  bool _sending = false;

  /// True after a conversation opens, until the athlete touches the screen or
  /// sends. While true, content that lays out late (long replies, cards that
  /// load after the messages) keeps the view on the newest message.
  bool _pinnedToEnd = false;
  bool _pinScheduled = false;

  /// A problem with the conversations themselves (loading, deleting).
  String? _error;

  /// The last send failed; shown under its question.
  _TurnFailure? _turnFailure;
  List<CoachFactSuggestion> _factSuggestions = const [];

  /// The suggestion being saved after Confirm.
  CoachFactSuggestion? _confirming;
  StreamSubscription<int>? _cooldownSubscription;
  int? _cooldownRemaining;

  /// The server says this month's Coach allowance is nearly used; shown
  /// under the newest reply.
  bool _budgetWarning = false;

  bool get _aiAllowed => widget.aiConsent?.granted ?? true;

  void _consentChanged() => setState(() {});

  /// Reloads the consent first: when the server refused for a notice the
  /// athlete's grant does not cover, the controller still says granted, and
  /// the sheet could not accept the new notice.
  Future<void> _reviewAiCoaching() async {
    final consent = widget.aiConsent!;
    try {
      await consent.load();
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
    if (!mounted) return;
    await showAiCoachingConsentSheet(context, consent);
  }

  @override
  void initState() {
    super.initState();
    widget.aiConsent?.addListener(_consentChanged);
    widget.draftRequests?.addListener(_takeDraft);
    _takeDraft();
    if (widget.repository is CoachContextRepository) {
      _contextStatus = (widget.repository as CoachContextRepository)
          .loadContextStatus();
    }
    WidgetsBinding.instance.addObserver(this);
    _restoreChat();
  }

  /// Puts a question another screen left into the composer: in an empty box,
  /// or under what the athlete had already typed. A conversation older than
  /// [coachReopenWindow] gives way to a fresh one first (a typed draft would
  /// otherwise keep it), so the question never lands in a stale chat.
  void _takeDraft() {
    final text = widget.draftRequests?.take();
    if (text == null) return;
    _startFreshIfStale();
    _addToComposer(text);
  }

  /// Puts [text] in the composer: in an empty box, or under what is typed.
  void _addToComposer(String text) {
    final typed = _composer.text;
    _composer.text = typed.trim().isEmpty ? text : '$typed\n\n$text';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
  }

  @override
  void didUpdateWidget(CoachScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftRequests != widget.draftRequests) {
      oldWidget.draftRequests?.removeListener(_takeDraft);
      widget.draftRequests?.addListener(_takeDraft);
    }
    if (oldWidget.aiConsent != widget.aiConsent) {
      oldWidget.aiConsent?.removeListener(_consentChanged);
      widget.aiConsent?.addListener(_consentChanged);
    }
    if (widget.active && !oldWidget.active) _startFreshIfStale();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      _startFreshIfStale();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.aiConsent?.removeListener(_consentChanged);
    widget.draftRequests?.removeListener(_takeDraft);
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
    // The last tick (zero seconds left) ends the cooldown itself; waiting for
    // the stream's done event would leave the composer off until it arrived.
    _cooldownSubscription = stream.listen((remaining) {
      if (!mounted) return;
      setState(() => _cooldownRemaining = remaining > 0 ? remaining : null);
      if (remaining <= 0) _sendQueued();
    });
  }

  /// Sends the waiting follow-up once Coach is free.
  void _sendQueued() {
    final text = _queuedFollowUp;
    if (text == null ||
        _sending ||
        _loadingChat ||
        _cooldownRemaining != null) {
      return;
    }
    setState(() => _queuedFollowUp = null);
    unawaited(_send(text));
  }

  /// A turn that did not complete leaves the waiting follow-up in the
  /// composer, to send or change, rather than answering a failed turn.
  void _queuedToComposer() {
    final text = _queuedFollowUp;
    if (text == null) return;
    setState(() => _queuedFollowUp = null);
    _addToComposer(text);
  }

  Future<void> _restoreChat() async {
    final chat = _chat;
    if (chat == null) {
      if (mounted) setState(() => _loadingChat = false);
      return;
    }
    final view = _view;
    try {
      final (threads, remembered) = await (
        chat.loadThreads(),
        widget.threadMemory.lastThreadId(),
      ).wait;
      // Reopen the conversation the user last had open; otherwise the one
      // with the newest message; with none, or none touched within
      // [coachReopenWindow], start a new conversation. The server bumps a
      // thread's updatedAt with every message, so it is the last message time.
      final last =
          threads.where((thread) => thread.id == remembered).firstOrNull ??
          threads.firstOrNull;
      final threadId =
          last != null &&
              widget.now().difference(last.updatedAt) < coachReopenWindow
          ? last.id
          : null;
      final messages = threadId == null
          ? const <CoachMessage>[]
          : await chat.loadMessages(threadId);
      if (!mounted) return;
      // The athlete may have opened or started a conversation meanwhile: the
      // list still applies, the selection does not.
      if (_view != view) {
        setState(() => _threads = threads);
        return;
      }
      setState(() {
        _threads = threads;
        _threadId = threadId;
        _previousThreadId = threadId == null ? last?.id : null;
        _threadRemembered = threads
            .where((thread) => thread.id == threadId)
            .every((thread) => thread.remember);
        _messages = messages;
        _loadingChat = false;
      });
      _showNewest();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted && _view == view) {
        setState(() {
          _loadingChat = false;
          _error = 'Saved conversations could not be loaded.';
        });
      }
    }
  }

  /// The open conversation's last activity: the later of its thread's
  /// updatedAt, its newest message and the moment the athlete opened it.
  DateTime? _lastActivity() {
    final id = _threadId;
    if (id == null) return null;
    final times = [
      ?_openedAt,
      for (final thread in _threads)
        if (thread.id == id) thread.updatedAt,
      for (final message in _messages) message.createdAt,
    ];
    return times.isEmpty ? null : times.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// The screen outlives a visit (tab switch, app in the background), so the
  /// [coachReopenWindow] is checked again when the athlete returns. Never
  /// while a turn is in flight or something is typed: the chat stays, and the
  /// next return checks again.
  void _startFreshIfStale() {
    if (_loadingChat || _sending || _composer.text.trim().isNotEmpty) return;
    final last = _lastActivity();
    if (last == null || widget.now().difference(last) < coachReopenWindow) {
      return;
    }
    _newThread(previous: _threadId);
  }

  Future<void> _openThread(String id) async {
    final chat = _chat;
    if (chat == null) return;
    // Only the first open of a run keeps what to go back to: a second tap
    // while the first still loads must not take the empty loading state for
    // the conversation the athlete was reading.
    final from =
        _openedFrom ??
        _OpenedFrom(
          view: _view,
          threadId: _threadId,
          previousThreadId: _previousThreadId,
          remembered: _threadRemembered,
          openedAt: _openedAt,
          messages: _messages,
          turnFailure: _turnFailure,
          factSuggestions: _factSuggestions,
          budgetWarning: _budgetWarning,
        );
    final view = _beginView();
    setState(() {
      _openedFrom = from;
      _openedAt = widget.now();
      _pinnedToEnd = false;
      _loadingChat = true;
      _threadId = id;
      _threadRemembered = _threads
          .where((thread) => thread.id == id)
          .every((thread) => thread.remember);
      _messages = const [];
      _error = null;
      _turnFailure = null;
      _factSuggestions = const [];
      _budgetWarning = false;
      _queuedFollowUp = null;
    });
    try {
      final messages = await chat.loadMessages(id);
      if (!mounted || _view != view) return;
      unawaited(widget.threadMemory.remember(id));
      setState(() {
        _openedFrom = null;
        _messages = messages;
        _loadingChat = false;
      });
      _showNewest();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (!mounted || _view != view) return;
      setState(() {
        _openedFrom = null;
        _view = from.view;
        _threadId = from.threadId;
        _previousThreadId = from.previousThreadId;
        _threadRemembered = from.remembered;
        _openedAt = from.openedAt;
        _messages = from.messages;
        _turnFailure = from.turnFailure;
        _factSuggestions = from.factSuggestions;
        _budgetWarning = from.budgetWarning;
        _loadingChat = false;
        _error = 'Conversation could not be opened.';
      });
    }
  }

  void _newThread({String? previous}) => setState(() {
    _beginView();
    _openedFrom = null;
    _openedAt = null;
    _previousThreadId = previous;
    _pinnedToEnd = false;
    _threadId = null;
    _rememberChat = true;
    _threadRemembered = true;
    _messages = const [];
    _loadingChat = false;
    _error = null;
    _turnFailure = null;
    _factSuggestions = const [];
    _budgetWarning = false;
    _queuedFollowUp = null;
  });

  /// Creates the server thread for a new conversation's first send. It is
  /// selected and listed (under its first question, the title the server
  /// gives it) only if the user is still on that conversation.
  Future<String> _startThread(
    CoachChatRepository chat,
    int view,
    String question,
  ) async {
    final remember = _rememberChat;
    final id = await chat.createThread(remember: remember);
    if (mounted && _view == view) {
      unawaited(widget.threadMemory.remember(id));
      setState(() {
        _threadId = id;
        _threadRemembered = remember;
        // A list requested before this thread existed would drop it, so it
        // no longer applies; this send's own refresh brings the server list.
        _threadsRequest++;
        _threads = [
          CoachThread(
            id: id,
            title: question,
            updatedAt: widget.now(),
            remember: remember,
          ),
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

  /// Sends a question as a new turn, or, with [retrying], asks a failed
  /// send again: repeating its idempotency key when no answer reached the
  /// app, so a turn the server finished after the timeout is returned and not
  /// run (and charged) a second time.
  Future<void> _send([String? suggestion, _TurnFailure? retrying]) async {
    final chat = _chat;
    final question = (suggestion ?? _composer.text).trim();
    if (chat == null || question.isEmpty || _loadingChat) return;
    if (_sending || _cooldownRemaining != null) {
      // A chip or "Change it" is never dropped: it waits, shown, and goes out
      // when Coach is free. Typing and Retry are off while busy.
      if (suggestion != null) setState(() => _queuedFollowUp = question);
      return;
    }
    if (!_aiAllowed) {
      await _reviewAiCoaching();
      return;
    }
    unawaited(TracendHaptics.light());
    // Retry and suggestion chips keep whatever the user is typing.
    if (suggestion == null) _composer.clear();
    _pinnedToEnd = false;
    final view = _view;
    final key = retrying != null && retrying.reuseKey
        ? retrying.key
        : _uuid.v4();
    final replays = retrying != null && retrying.reuseKey
        ? retrying.replays + 1
        : 0;
    // A retry stands in for the failed attempt, whatever key it uses: with a
    // new key the server marks the failed attempt's saved question
    // superseded, and the thread view hides it, so one bubble is what the
    // thread shows.
    final pending = _messages.lastOrNull;
    final local =
        retrying != null &&
            pending != null &&
            pending.role == 'user' &&
            pending.id.startsWith('pending-') &&
            pending.content == question
        ? pending
        : CoachMessage(
            id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
            role: 'user',
            content: question,
            createdAt: widget.now(),
          );
    setState(() {
      if (!_messages.contains(local)) _messages = [..._messages, local];
      _sending = true;
      _turnFailure = null;
      _factSuggestions = const [];
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
          _queuedToComposer();
        }
        unawaited(_refreshThreads(chat));
        return;
      }
      final answer = await chat.sendMessage(
        threadId,
        question,
        idempotencyKey: key,
      );
      var suggestions = const <CoachFactSuggestion>[];
      if (chat is CoachRawResponses) {
        suggestions = CoachFactSuggestion.listFromResponse(
          await (chat as CoachRawResponses).loadLastRawResponse(),
        );
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
            _factSuggestions = suggestions;
            _budgetWarning = answer.nearBudgetLimit;
          }
          _sending = false;
        });
        _scrollToEnd();
        _sendQueued();
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
        final failure = _describeFailure(e, question, key, replays);
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
        _queuedToComposer();
      }
    }
    unawaited(_refreshThreads(chat));
  }

  /// What to say about a failed send, in plain words, with the raw text as
  /// the beta diagnostic. During the private beta the raw text stays visible
  /// (with its HTTP status and the server's stable code) so the owner can
  /// see where a failure comes from (owner decision, 2026-09-27).
  _TurnFailure _describeFailure(
    Object error,
    String question,
    String key,
    int replays,
  ) {
    final failure = coachChatFailure(error, now: DateTime.now());
    return (
      message: failure.message,
      diagnostic: failure.betaDiagnostic,
      question: question,
      key: key,
      replays: replays,
      reuseKey: failure.retrySameKey && replays < _maxKeyReplays,
      retryable: failure.retryable,
      needsConsent: failure.needsConsent,
    );
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

  /// Opens the view on the newest message and keeps it there while the
  /// content settles (see [_pinnedToEnd]).
  void _showNewest() {
    _pinnedToEnd = true;
    _scrollToEnd(animate: false);
  }

  /// Layout changes while pinned (a late card, a long reply) move the end
  /// further down: follow it.
  bool _followEnd(ScrollMetricsNotification notification) {
    if (!_pinnedToEnd || notification.depth != 0 || _pinScheduled) return false;
    _pinScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinScheduled = false;
      if (!mounted || !_pinnedToEnd || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if ((end - _scroll.position.pixels).abs() > 0.5) _scroll.jumpTo(end);
    });
    return false;
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

  /// The athlete tapped Confirm: only now is anything written, as their own
  /// action. An update replaces the saved fact it names; a resolve deletes it.
  Future<void> _confirmSuggestion(CoachFactSuggestion suggestion) async {
    final memory = widget.memory;
    if (memory == null || _confirming != null) return;
    setState(() => _confirming = suggestion);
    try {
      if (suggestion.action == CoachFactSuggestionAction.resolve) {
        await memory.deleteFact(suggestion.factId!);
      } else if (suggestion.action == CoachFactSuggestionAction.reconfirm) {
        await memory.reconfirmFact(suggestion.factId!);
      } else {
        await memory.saveFact(
          kind: suggestion.kind,
          subject: suggestion.subject,
          statement: suggestion.statement,
          source: CoachFactSource.coachSuggestionConfirmed,
          supersedes: suggestion.factId,
        );
      }
      if (!mounted) return;
      TracendToast.show(
        context,
        suggestion.action == CoachFactSuggestionAction.resolve
            ? 'Coach forgot it'
            : suggestion.action == CoachFactSuggestionAction.reconfirm
            ? 'Confirmed again'
            : 'Saved to what Coach remembers',
      );
      setState(() {
        _factSuggestions = [
          for (final item in _factSuggestions)
            if (item != suggestion) item,
        ];
        _confirming = null;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _confirming = null;
          _error = isFactLimitError(e)
              ? 'You have saved the most Coach keeps. Delete a fact first.'
              : 'It could not be saved. Nothing was changed.';
        });
      }
    }
  }

  void _dismissSuggestion(CoachFactSuggestion suggestion) => setState(() {
    _factSuggestions = [
      for (final item in _factSuggestions)
        if (item != suggestion) item,
    ];
  });

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
    } catch (e, stackTrace) {
      debugPrint('Non-critical error: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
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
                _newThread(previous: _threadId ?? _previousThreadId);
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
            // Touching the conversation ends the follow-the-newest pin, so a
            // tap that expands a card does not jump away.
            child: Listener(
              onPointerDown: (_) => _pinnedToEnd = false,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _followEnd,
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

  /// The questions offered on a new conversation. Context status that reports
  /// no approved plan swaps the plan questions for ones that work without it.
  List<String> _suggestions(List<CoachContextSource>? sources) {
    final noPlan = sources?.any(
      (source) => source.key == 'approved_plan' && !source.available,
    );
    return noPlan ?? false
        ? const [
            'What can you help me with?',
            'Why don’t I have a plan yet?',
            'What should I do next?',
          ]
        : const [
            'What should I do next?',
            'Explain today’s evidence',
            'What is my next meal?',
          ];
  }

  List<Widget> _content(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final failure = _turnFailure;
    // A new conversation offers the one before it.
    final previous = _threadId == null
        ? _threads
                  .where((thread) => thread.id == _previousThreadId)
                  .firstOrNull ??
              _threads.firstOrNull
        : null;
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
                'The Coach sends your Tracend data to an AI service to answer, '
                'so it needs your permission first.',
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
      if (!_loadingChat && !_threadRemembered) ...[
        const _NotRememberedNotice(),
        const SizedBox(height: TracendSpacing.md),
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
        // The choice is made before the first message and cannot change after.
        if (_threadId == null)
          TracendGroupedList(
            children: [
              TracendListRow(
                title: 'Don’t remember this chat',
                subtitle:
                    'Coach saves no notes or facts from it, never searches it '
                    'and no other chat sees it.',
                trailing: Semantics(
                  label: 'Don’t remember this chat',
                  child: CupertinoSwitch(
                    value: !_rememberChat,
                    onChanged: _sending
                        ? null
                        : (value) => setState(() => _rememberChat = !value),
                  ),
                ),
              ),
            ],
          ),
        if (_threadId == null) const SizedBox(height: TracendSpacing.md),
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
        if (previous != null) ...[
          TracendGroupedList(
            children: [
              TracendListRow(
                title: 'Continue last chat',
                subtitle: _ThreadRow._title(previous.title),
                onTap: () => _openThread(previous.id),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.lg),
        ],
        // Padded chips already keep 8pt between rows. An athlete without an
        // approved plan is offered questions the Coach can answer for them.
        FutureBuilder<List<CoachContextSource>>(
          future: _contextStatus,
          builder: (context, snapshot) => Wrap(
            spacing: TracendSpacing.xs,
            children: [
              for (final suggestion in _suggestions(snapshot.data))
                ActionChip(
                  label: Text(suggestion),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => _send(suggestion),
                ),
            ],
          ),
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
          if (message.proposalId case final proposalId?
              when widget.proposals != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            CoachProposalLoader(
              key: ValueKey('proposal-$proposalId'),
              proposalId: proposalId,
              repository: widget.proposals!,
              onPlanChanged: widget.planChanges?.announce,
              onChangeIt: (proposal) => _send(proposal.changeRequestMessage),
            ),
          ],
        ],
      if (_budgetWarning && failure == null && !_sending) ...[
        const SizedBox(height: TracendSpacing.md),
        _Notice(coachBudgetWarningMessage(DateTime.now())),
      ],
      if (failure != null && !_loadingChat) ...[
        const SizedBox(height: TracendSpacing.md),
        CoachTurnError(
          message: failure.message,
          diagnostic: failure.diagnostic,
          onRetry: !failure.retryable || _sending || _cooldownRemaining != null
              ? null
              : () => _send(failure.question, failure),
          actionLabel: failure.needsConsent && widget.aiConsent != null
              ? 'Review AI coaching'
              : null,
          onAction: failure.needsConsent && widget.aiConsent != null
              ? _reviewAiCoaching
              : null,
        ),
      ],
      if (_sending) ...[
        const SizedBox(height: TracendSpacing.md),
        const Align(
          alignment: Alignment.centerLeft,
          child: CoachThinkingIndicator(),
        ),
      ],
      if (_queuedFollowUp case final queued?) ...[
        const SizedBox(height: TracendSpacing.md),
        _QueuedFollowUp(
          text: queued,
          onCancel: () => setState(() => _queuedFollowUp = null),
        ),
      ],
      if (widget.memory != null)
        for (final suggestion in _factSuggestions) ...[
          const SizedBox(height: TracendSpacing.lg),
          FactSuggestionChip(
            suggestion: suggestion,
            busy: _confirming == suggestion,
            onConfirm: () => _confirmSuggestion(suggestion),
            onDismiss: () => _dismissSuggestion(suggestion),
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
            subtitle: [
              if (open) 'Open now',
              updated,
              if (!thread.remember) 'Not remembered',
            ].join(' · '),
            onTap: onOpen,
          ),
        ),
      ),
    );
  }
}

/// Shown at the top of a conversation the athlete asked Coach not to
/// remember.
class _NotRememberedNotice extends StatelessWidget {
  const _NotRememberedNotice();

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
              CupertinoIcons.eye_slash,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Text(
              'This chat isn’t remembered. Coach saves no notes or facts from '
              'it, and other chats can’t see it.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A follow-up waiting for Coach to finish, with a way to cancel it.
class _QueuedFollowUp extends StatelessWidget {
  const _QueuedFollowUp({required this.text, required this.onCancel});

  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.clock, size: 18, color: colors.textSecondary),
        const SizedBox(width: TracendSpacing.xs),
        Expanded(
          child: Text(
            'Sends when Coach is ready: $text',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
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
