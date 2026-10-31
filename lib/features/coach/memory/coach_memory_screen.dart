import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/coach/memory/coach_fact_editor.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// What Coach remembers (UX_FLOWS.md, Account). The facts the athlete
/// confirmed come first, each with where it came from and when; the athlete
/// can add, edit, confirm again and delete them. Under them are Coach's own
/// notes about past conversations, which can be read and deleted. At the foot,
/// "Forget everything". Nothing here changes unless the athlete does it.
class CoachMemoryScreen extends StatefulWidget {
  const CoachMemoryScreen({required this.repository, super.key});

  final CoachMemoryRepository repository;

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

enum _FactAction { stillTrue, edit, delete }

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  CoachMemory? _memory;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_memory == null) setState(() => _failed = false);
    try {
      final memory = await widget.repository.load();
      if (mounted) {
        setState(() {
          _memory = memory;
          _failed = false;
        });
      }
    } catch (e, stackTrace) {
      logNonCritical(e);
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
      if (mounted && _memory == null) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What Coach remembers')),
    body: SafeArea(top: false, child: _body(context)),
  );

  Widget _body(BuildContext context) {
    final memory = _memory;
    if (memory != null) return _content(context, memory);
    if (_failed) {
      return AccountDetailMessage(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Coach’s memory could not load',
        detail: 'Nothing was changed. Check your connection and try again.',
        action: OutlinedButton(
          onPressed: _load,
          child: const Text('Try again'),
        ),
      );
    }
    return const Center(
      child: TracendLoader(semanticLabel: 'Loading what Coach remembers'),
    );
  }

  Widget _content(BuildContext context, CoachMemory memory) {
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    final textTheme = Theme.of(context).textTheme;
    final byKind = <CoachFactKind, List<CoachFact>>{
      for (final kind in CoachFactKind.values)
        kind: [
          for (final fact in memory.facts)
            if (fact.kind == kind) fact,
        ],
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        TracendSpacing.xs,
        gutter,
        TracendSpacing.xxl,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
          ),
          child: Text(
            'Coach uses what is saved here to answer you. Only you can add or '
            'change a fact; Coach can suggest one and asks before it saves '
            'anything.',
            style: textTheme.bodyMedium,
          ),
        ),
        const SectionLabel('Facts you confirmed'),
        if (memory.facts.isEmpty)
          const AccountFootnote(
            'Nothing is saved yet. When you tell Coach something that lasts, '
            'such as an injury or a food you avoid, it asks before saving it.',
          ),
        for (final kind in CoachFactKind.values)
          if (byKind[kind]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TracendListRow.horizontalPadding,
                TracendSpacing.sm,
                0,
                TracendSpacing.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(kind.label, style: textTheme.titleSmall),
              ),
            ),
            TracendGroupedList(
              children: [
                for (final fact in byKind[kind]!) _factRow(context, fact),
              ],
            ),
          ],
        const SizedBox(height: TracendSpacing.md),
        TracendGroupedList(
          children: [
            TracendListRow(
              title: 'Add something Coach should know',
              subtitle: memory.factsFull
                  ? 'You have saved the most Coach keeps '
                        '(${memory.limits.maxFacts}). Delete one to add another.'
                  : null,
              leading: const TracendRowIcon(icon: CupertinoIcons.add),
              onTap: memory.factsFull ? null : () => _addFact(memory),
            ),
          ],
        ),
        const SectionLabel('Coach’s notes'),
        AccountFootnote(
          'Coach’s own short notes on past chats and advice, written without '
          'AI. They can be out of date. Coach keeps the last '
          '${memory.limits.maxNotes}, each for ${memory.limits.noteDays} days.',
        ),
        const SizedBox(height: TracendSpacing.xs),
        if (memory.notes.isEmpty)
          const AccountFootnote(
            'No notes yet. A chat you ask Coach not to remember never adds one.',
          )
        else
          TracendGroupedList(
            children: [for (final note in memory.notes) _noteRow(note)],
          ),
        const SizedBox(height: TracendSpacing.xl),
        OutlinedButton(
          onPressed: memory.isEmpty ? null : () => _forgetAll(memory),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.tracendColors.stateDanger,
          ),
          child: const Text('Forget everything'),
        ),
        const AccountFootnote(
          'Deletes every fact and note above. Your conversations, plan and '
          'logged data stay as they are.',
        ),
      ],
    );
  }

  Widget _factRow(BuildContext context, CoachFact fact) {
    final subtitle = [
      'Confirmed ${fullDate(fact.confirmedAt)}',
      fact.source.label,
    ].join(' · ');
    return TracendListRow(
      title: fact.statement,
      subtitle: fact.reconfirmDue
          ? '$subtitle\nCheck that this still applies'
          : subtitle,
      leading: TracendRowIcon(
        icon: fact.reconfirmDue
            ? CupertinoIcons.clock
            : CupertinoIcons.checkmark_seal,
        color: fact.reconfirmDue ? context.tracendColors.stateAttention : null,
      ),
      onTap: () => _openFact(fact),
    );
  }

  Widget _noteRow(CoachNote note) {
    final through = note.followThrough;
    return TracendListRow(
      title: note.summary,
      subtitle: [
        fullDate(note.noteDate),
        if (through != null)
          through.detail.isEmpty
              ? through.label
              : '${through.label} (${through.detail})',
      ].join(' · '),
      leading: TracendRowIcon(
        icon: note.isAdvice
            ? CupertinoIcons.lightbulb
            : CupertinoIcons.text_bubble,
      ),
      trailing: IconButton(
        tooltip: 'Delete note',
        onPressed: () => _deleteNote(note),
        icon: const Icon(CupertinoIcons.trash, size: 18),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }

  // Facts -------------------------------------------------------------------------------------

  Future<void> _openFact(CoachFact fact) async {
    final action = await showTracendSheet<_FactAction>(
      context,
      title: fact.kind.label,
      builder: (sheetContext) => _FactDetail(fact: fact),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _FactAction.stillTrue:
        await _reconfirm(fact);
      case _FactAction.edit:
        await _editFact(fact);
      case _FactAction.delete:
        await _deleteFact(fact);
    }
  }

  Future<void> _addFact(CoachMemory memory) => _showEditor(initial: null);

  Future<void> _editFact(CoachFact fact) => _showEditor(initial: fact);

  Future<void> _showEditor({required CoachFact? initial}) async {
    final saved = await showTracendSheet<bool>(
      context,
      title: initial == null ? 'Add a fact' : 'Edit this fact',
      subtitle: 'Only what you write here is saved.',
      builder: (sheetContext) => CoachFactEditor(
        initial: initial,
        save: (kind, statement) => widget.repository.saveFact(
          kind: kind,
          subject: coachFactSubjectFor(statement),
          statement: statement,
          supersedes: initial?.id,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    TracendToast.show(context, initial == null ? 'Fact saved' : 'Fact updated');
    await _load();
  }

  Future<void> _reconfirm(CoachFact fact) async {
    try {
      await widget.repository.reconfirmFact(fact.id);
    } catch (e, stackTrace) {
      _failure('The fact could not be confirmed', e, stackTrace);
      return;
    }
    if (!mounted) return;
    TracendToast.show(context, 'Confirmed again');
    await _load();
  }

  Future<void> _deleteFact(CoachFact fact) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this fact?',
      message:
          'Coach forgets “${fact.statement}”, including its earlier versions.',
      confirmLabel: 'Delete fact',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.deleteFact(fact.id);
    } catch (e, stackTrace) {
      _failure('The fact could not be deleted', e, stackTrace);
      return;
    }
    if (!mounted) return;
    TracendToast.show(context, 'Fact deleted');
    await _load();
  }

  // Notes and everything ---------------------------------------------------------------------

  Future<void> _deleteNote(CoachNote note) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this note?',
      message: 'Coach forgets what this note says.',
      confirmLabel: 'Delete note',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.deleteNote(note.id);
    } catch (e, stackTrace) {
      _failure('The note could not be deleted', e, stackTrace);
      return;
    }
    if (!mounted) return;
    TracendToast.show(context, 'Note deleted');
    await _load();
  }

  Future<void> _forgetAll(CoachMemory memory) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Forget everything?',
      message:
          'Coach forgets all ${memory.facts.length} saved facts and '
          '${memory.notes.length} notes. Your conversations, plan and logged '
          'data stay. This cannot be undone.',
      confirmLabel: 'Forget everything',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.forgetAll();
    } catch (e, stackTrace) {
      _failure('Coach could not forget everything', e, stackTrace);
      return;
    }
    if (!mounted) return;
    TracendToast.show(context, 'Coach forgot everything');
    await _load();
  }

  void _failure(String message, Object error, StackTrace stackTrace) {
    logNonCritical(error);
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    if (!mounted) return;
    TracendToast.show(
      context,
      '$message. Nothing was changed.',
      icon: CupertinoIcons.exclamationmark_circle,
    );
  }
}

/// A fact in a sheet: its words, where it came from and when, and the three
/// things the athlete can do with it.
class _FactDetail extends StatelessWidget {
  const _FactDetail({required this.fact});

  final CoachFact fact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fact.statement, style: textTheme.bodyLarge),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            '${fact.source.label}. Confirmed ${fullDate(fact.confirmedAt)}.',
            style: textTheme.bodySmall,
          ),
          if (fact.reconfirmAt != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              fact.reconfirmDue
                  ? 'Coach would like to check that this still applies.'
                  : 'Coach will check again after '
                        '${fullDate(fact.reconfirmAt!)}.',
              style: textTheme.bodySmall?.copyWith(
                color: fact.reconfirmDue ? colors.stateAttention : null,
              ),
            ),
          ],
          const SizedBox(height: TracendSpacing.md),
          if (fact.reconfirmAt != null) ...[
            FilledButton(
              onPressed: () => Navigator.pop(context, _FactAction.stillTrue),
              child: const Text('Still true'),
            ),
            const SizedBox(height: TracendSpacing.xs),
          ],
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _FactAction.edit),
            child: const Text('Edit'),
          ),
          const SizedBox(height: TracendSpacing.xs),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _FactAction.delete),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.stateDanger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
