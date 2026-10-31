import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
import 'package:tracend/shared/diagnostics.dart';

/// The body of the add and edit sheet on the memory screen: a kind from the
/// closed list and the athlete's own words. [save] runs when Save is tapped;
/// the sheet closes with `true` only if it succeeds, and says so here if not,
/// so a typed fact is never lost to a failed save.
class CoachFactEditor extends StatefulWidget {
  const CoachFactEditor({required this.save, this.initial, super.key});

  /// The fact being edited, or null for a new one.
  final CoachFact? initial;
  final Future<Object?> Function(CoachFactKind kind, String statement) save;

  @override
  State<CoachFactEditor> createState() => _CoachFactEditorState();
}

class _CoachFactEditorState extends State<CoachFactEditor> {
  static const _maxChars = 200;

  late final TextEditingController _text;
  late CoachFactKind _kind;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial?.statement ?? '');
    _kind = widget.initial?.kind ?? CoachFactKind.otherPreference;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _statement => _text.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  bool get _changed {
    final initial = widget.initial;
    return initial == null ||
        _statement != initial.statement ||
        _kind != initial.kind;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_kind, _statement);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      logNonCritical(e);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = isFactLimitError(e)
              ? 'You have saved the most Coach keeps. Delete a fact first.'
              : 'It could not be saved. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What is it about?', style: textTheme.titleSmall),
          const SizedBox(height: TracendSpacing.xs),
          Wrap(
            spacing: TracendSpacing.xs,
            children: [
              for (final kind in CoachFactKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kind == kind,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: _saving
                      ? null
                      : (selected) {
                          if (selected) setState(() => _kind = kind);
                        },
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.md),
          TextField(
            controller: _text,
            enabled: !_saving,
            maxLength: _maxChars,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'In your words',
              hintText: 'For example: left knee hurts on deep squats',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(color: colors.stateDanger),
            ),
          ],
          const SizedBox(height: TracendSpacing.md),
          FilledButton(
            onPressed: _saving || _statement.isEmpty || !_changed
                ? null
                : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
