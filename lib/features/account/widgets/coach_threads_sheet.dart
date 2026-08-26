import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';

/// Coach conversation list. Rows are display-only; the trailing delete
/// control is the action (Chunk 4 decision — no dead chevron).
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
    try {
      await widget.chat.deleteThread(thread.id);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() => _error = 'The conversation could not be deleted.');
      }
      return;
    }
    if (!mounted) return;
    setState(
      () => _threads = _threads?.where((item) => item.id != thread.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Builder(
      builder: (context) {
        final threads = _threads;
        return ListView(
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          children: [
            Text(
              'Coach conversations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xs),
            const Text(
              'Messages remain until you delete a thread or delete your account.',
            ),
            const SizedBox(height: TracendSpacing.md),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: context.tracendColors.stateDanger),
              )
            else if (threads == null)
              const Center(child: CircularProgressIndicator())
            else if (threads.isEmpty)
              const Text('No saved conversations.')
            else
              for (final thread in threads)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(thread.title),
                  trailing: IconButton(
                    tooltip: 'Delete conversation',
                    icon: const Icon(CupertinoIcons.delete),
                    onPressed: () => _delete(thread),
                  ),
                ),
          ],
        );
      },
    ),
  );
}
