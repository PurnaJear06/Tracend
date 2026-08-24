import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_composer.dart';
import 'package:tracend/features/coach/widgets/coach_context_card.dart';
import 'package:tracend/features/coach/widgets/coach_decision_card.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/widgets/preference_prompt_chip.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({
    this.repository = const FixtureCoachRepository(),
    super.key,
  });
  final CoachRepository repository;
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  late Future<CoachDecision?> _decision;
  Future<List<CoachContextSource>>? _contextStatus;
  CoachChatRepository? get _chat => widget.repository is CoachChatRepository
      ? widget.repository as CoachChatRepository
      : null;
  List<CoachThread> _threads = const [];
  List<CoachMessage> _messages = const [];
  String? _threadId;
  bool _loadingChat = true;
  bool _sending = false;
  bool _generating = false;
  String? _error;
  Map<String, dynamic>? _preferencePrompt;
  StreamSubscription<int>? _cooldownSubscription;
  int? _cooldownRemaining;

  @override
  void initState() {
    super.initState();
    _decision = widget.repository.loadLatest();
    if (widget.repository is CoachContextRepository) {
      _contextStatus = (widget.repository as CoachContextRepository)
          .loadContextStatus();
    }
    _restoreChat();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
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
      final threads = await chat.loadThreads();
      final threadId = threads.isEmpty
          ? await chat.createThread()
          : threads.first.id;
      final messages = await chat.loadMessages(threadId);
      if (!mounted) return;
      setState(() {
        _threads = threads.isEmpty
            ? [
                CoachThread(
                  id: threadId,
                  title: 'New conversation',
                  updatedAt: DateTime.now(),
                ),
              ]
            : threads;
        _threadId = threadId;
        _messages = messages;
        _loadingChat = false;
      });
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
    Navigator.of(context).pop();
    setState(() {
      _loadingChat = true;
      _threadId = id;
    });
    try {
      final messages = await chat.loadMessages(id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _loadingChat = false;
        });
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

  Future<void> _newThread() async {
    final chat = _chat;
    if (chat == null) return;
    final id = await chat.createThread();
    if (!mounted) return;
    setState(() {
      _threadId = id;
      _messages = const [];
      _threads = [
        CoachThread(
          id: id,
          title: 'New conversation',
          updatedAt: DateTime.now(),
        ),
        ..._threads,
      ];
    });
  }

  Future<void> _send([String? suggestion]) async {
    final chat = _chat;
    final threadId = _threadId;
    final question = (suggestion ?? _composer.text).trim();
    if (chat == null || threadId == null || question.isEmpty || _sending) {
      return;
    }
    _composer.clear();
    final local = CoachMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: question,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, local];
      _sending = true;
      _error = null;
      _preferencePrompt = null;
    });
    _scrollToEnd();
    final started = DateTime.now();
    try {
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
        await HapticFeedback.lightImpact();
        setState(() {
          _messages = [..._messages, answer];
          _preferencePrompt = prompt;
          _sending = false;
        });
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) {
        int? retrySec;
        if (e is CoachUnavailableException) {
          retrySec = e.retryAfterSeconds;
          if (retrySec != null && retrySec > 0) {
            _startCooldown(retrySec);
          }
        }
        final msg = e is TimeoutException
            ? 'Coach took too long to respond. Please try again.'
            : e
                  .toString()
                  .replaceFirst('Exception: ', '')
                  .replaceFirst('StateError: ', '');
        final elapsed = DateTime.now().difference(started);
        if (chat is SupabaseCoachRepository &&
            elapsed < const Duration(milliseconds: 1200)) {
          await Future.delayed(const Duration(milliseconds: 1200) - elapsed);
          if (!mounted) return;
        }
        setState(() {
          _sending = false;
          _error = msg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: TracendMotion.standard,
            curve: TracendMotion.curve,
          ),
        );
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final value = await widget.repository.generate();
      if (mounted) setState(() => _decision = Future.value(value));
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _error =
              'Coaching is unavailable. Your approved plan is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showThreads() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => ListView(
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Saved conversations',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _newThread();
              },
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.sm),
        for (final thread in _threads)
          ListTile(
            selected: thread.id == _threadId,
            leading: const Icon(CupertinoIcons.bubble_left),
            title: Text(
              thread.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openThread(thread.id),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Coach'),
      actions: [
        IconButton(
          tooltip: 'Saved conversations',
          onPressed: _showThreads,
          icon: const Icon(CupertinoIcons.sidebar_left),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                TracendSpacing.gutter,
                TracendSpacing.sm,
                TracendSpacing.gutter,
                TracendSpacing.lg,
              ),
              children: [
                FutureBuilder<CoachDecision?>(
                  future: _decision,
                  builder: (context, snapshot) => CoachDecisionCard(
                    decision: snapshot.data,
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                    generating: _generating,
                    onGenerate: _generate,
                  ),
                ),
                if (_contextStatus != null) ...[
                  const SizedBox(height: TracendSpacing.sm),
                  FutureBuilder<List<CoachContextSource>>(
                    future: _contextStatus,
                    builder: (context, snapshot) => CoachContextCard(
                      sources: snapshot.data,
                      loading:
                          snapshot.connectionState == ConnectionState.waiting,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: TracendSpacing.sm),
                  TracendCard(
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: context.tracendColors.stateAttention,
                        ),
                        const SizedBox(width: TracendSpacing.sm),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ],
                if (_preferencePrompt != null) ...[
                  const SizedBox(height: TracendSpacing.sm),
                  PreferencePromptChip(
                    category:
                        _preferencePrompt!['category'] as String? ?? 'food',
                    prefKey: _preferencePrompt!['key'] as String? ?? '',
                    value: _preferencePrompt!['value'] as String? ?? '',
                    onConfirm: () {
                      final chat = _chat;
                      if (chat is SupabaseCoachRepository) {
                        chat.confirmPreference(
                          category:
                              _preferencePrompt!['category'] as String? ??
                              'food',
                          key: _preferencePrompt!['key'] as String? ?? '',
                          value: _preferencePrompt!['value'] as String? ?? '',
                          provenance:
                              _preferencePrompt!['provenance'] as String? ??
                              'chat_statement',
                        );
                      }
                      setState(() => _preferencePrompt = null);
                    },
                    onDismiss: () => setState(() => _preferencePrompt = null),
                  ),
                ],
                const SectionLabel('Conversation'),
                if (_loadingChat)
                  const LinearProgressIndicator(minHeight: 3)
                else if (_messages.isEmpty) ...[
                  const TracendCard(
                    child: Text(
                      'Ask about training, meals, recovery, progress, evidence, or how to use Tracend. The Coach cannot silently change your plan or confirmed data.',
                    ),
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  Wrap(
                    spacing: TracendSpacing.xs,
                    runSpacing: TracendSpacing.xs,
                    children: [
                      for (final prompt in const [
                        'What should I do next?',
                        'Explain today’s evidence',
                        'What is my next meal?',
                      ])
                        ActionChip(
                          label: Text(prompt),
                          onPressed: () => _send(prompt),
                        ),
                    ],
                  ),
                ] else
                  for (final message in _messages) ...[
                    CoachMessageBubble(
                      message: message,
                      onSendFollowUp: (prompt) => _send(prompt),
                    ),
                    const SizedBox(height: TracendSpacing.sm),
                  ],
                if (_sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TracendPill(
                      label: 'Coach is reviewing your evidence',
                      icon: CupertinoIcons.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          CoachComposer(
            controller: _composer,
            enabled: !_sending && _chat != null && _cooldownRemaining == null,
            cooldownRemaining: _cooldownRemaining,
            onSend: _send,
          ),
        ],
      ),
    ),
  );
}
