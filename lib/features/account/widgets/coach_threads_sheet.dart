import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Saved Coach conversations, the body of a Tracend sheet. Rows are
/// display-only; the trailing delete control is the action, and it asks
/// first because a deleted thread cannot come back.
class CoachThreadsSheet extends StatefulWidget {
  const CoachThreadsSheet({required this.chat, super.key});

  final CoachChatRepository chat;

  @override
  State<CoachThreadsSheet> createState() => _CoachThreadsSheetState();
}

class _CoachThreadsSheetState extends State<CoachThreadsSheet> {
  List<CoachThread>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await widget.chat.loadThreads();
      if (mounted) setState(() => _threads = threads);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) setState(() => _error = 'Conversations could not load.');
    }
  }

  Future<void> _delete(CoachThread thread) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this conversation?',
      message: 'Its messages are removed for good.',
      confirmLabel: 'Delete thread',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.chat.deleteThread(thread.id);
    } catch (e, stackTrace) {
      debugPrint('Non-critical error: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      if (mounted) {
        setState(() => _error = 'The conversation could not be deleted.');
      }
      return;
    }
    if (!mounted) return;
    setState(
      () => _threads = _threads?.where((item) => item.id != thread.id).toList(),
    );
    TracendToast.show(context, 'Conversation deleted');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final threads = _threads;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Messages stay until you delete a conversation or your account.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.md),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(
                color: context.tracendColors.stateDanger,
              ),
            ),
          )
        else if (threads == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: TracendSpacing.lg),
            child: Center(
              child: TracendLoader(semanticLabel: 'Loading conversations'),
            ),
          )
        else if (threads.isEmpty)
          Text('No saved conversations.', style: textTheme.bodyLarge)
        else
          TracendGroupedList(
            children: [
              for (final thread in threads)
                TracendListRow(
                  title: thread.title,
                  trailing: IconButton(
                    tooltip: 'Delete conversation',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: Icon(
                      CupertinoIcons.delete,
                      size: 20,
                      color: context.tracendColors.stateDanger,
                    ),
                    onPressed: () => _delete(thread),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
