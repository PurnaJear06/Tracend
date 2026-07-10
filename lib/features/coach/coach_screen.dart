import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _decision = widget.repository.loadLatest();
    _restoreChat();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
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
    } catch (_) {
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
    } catch (_) {
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
    });
    _scrollToEnd();
    try {
      final answer = await chat.sendMessage(threadId, question);
      if (mounted) {
        await HapticFeedback.lightImpact();
        setState(() {
          _messages = [..._messages, answer];
          _sending = false;
        });
        _scrollToEnd();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error =
              'Coach is unavailable. Your approved plan and logs are unchanged.';
        });
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
    } catch (_) {
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
                  builder: (context, snapshot) => _PinnedDecision(
                    decision: snapshot.data,
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                    generating: _generating,
                    onGenerate: _generate,
                  ),
                ),
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
                    _MessageBubble(message: message),
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
          _Composer(
            controller: _composer,
            enabled: !_sending && _chat != null,
            onSend: _send,
          ),
        ],
      ),
    ),
  );
}

class _PinnedDecision extends StatelessWidget {
  const _PinnedDecision({
    required this.decision,
    required this.loading,
    required this.generating,
    required this.onGenerate,
  });
  final CoachDecision? decision;
  final bool loading;
  final bool generating;
  final VoidCallback onGenerate;
  @override
  Widget build(BuildContext context) {
    if (loading) return const TracendCard(child: LinearProgressIndicator());
    if (decision == null) {
      return TracendCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No daily decision yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TracendSpacing.xs),
            const Text(
              'Generate one from your approved plan and latest confirmed evidence.',
            ),
            const SizedBox(height: TracendSpacing.sm),
            FilledButton(
              onPressed: generating ? null : onGenerate,
              child: const Text('Generate today’s decision'),
            ),
          ],
        ),
      );
    }
    return TracendCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.pin_fill,
                color: context.tracendColors.actionPrimary,
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Text(
                  'Head Coach · ${decision!.confidence} confidence',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            decision!.finalDecision,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(decision!.reason),
          if (decision!.evidence.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            for (final item in decision!.evidence)
              Text(
                item['label'] as String,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
          const SizedBox(height: TracendSpacing.sm),
          OutlinedButton(
            onPressed: generating ? null : onGenerate,
            child: const Text('Refresh decision'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final CoachMessage message;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final colors = context.tracendColors;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: user ? 'You said' : 'Coach said',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(TracendSpacing.md),
          decoration: BoxDecoration(
            color: user ? colors.actionPrimary : colors.surface,
            border: user ? null : Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(user ? 18 : 4),
              bottomRight: Radius.circular(user ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.content,
                style: TextStyle(
                  color: user ? colors.actionOnPrimary : colors.textPrimary,
                  height: 1.45,
                ),
              ),
              if (!user &&
                  (message.evidence.isNotEmpty ||
                      message.missingData.isNotEmpty)) ...[
                const SizedBox(height: TracendSpacing.xs),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Evidence and limits'),
                  children: [
                    for (final item in message.evidence)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(item['label'] as String),
                        subtitle: Text(item['source'] as String),
                      ),
                    if (message.missingData.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Missing: ${message.missingData.join(', ')}',
                        ),
                      ),
                  ],
                ),
              ],
              if (!user && message.suggestedFollowUps.isNotEmpty) ...[
                const SizedBox(height: TracendSpacing.xs),
                for (final prompt in message.suggestedFollowUps)
                  Text(
                    '• $prompt',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tracendColors.canvas,
        border: Border(
          top: BorderSide(color: context.tracendColors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.gutter,
          TracendSpacing.sm,
          TracendSpacing.gutter,
          TracendSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: 'Ask your Coach',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: TracendSpacing.xs),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: enabled ? onSend : null,
              icon: const Icon(CupertinoIcons.arrow_up),
            ),
          ],
        ),
      ),
    ),
  );
}
