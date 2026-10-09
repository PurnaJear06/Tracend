import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/features/consent/widgets/ai_notice_panel.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';

const _confidenceLabels = {
  'low': 'Low confidence',
  'medium': 'Medium confidence',
  'high': 'High confidence',
};

List<String> _names(List<String> muscles) => [
  for (final muscle in muscles)
    (physiqueMuscleLabels[muscle] ?? muscle).toLowerCase(),
];

/// "chest" or "chest and calves", for sentences.
String _muscleList(List<String> muscles) {
  final names = _names(muscles);
  if (names.length < 2) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// One-line summary of a check for the photo card: the confirmed focus, or
/// what the check suggested when nothing was confirmed.
String physiqueFocusSummary(PhysiqueAnalysis analysis) {
  if (analysis.confirmedMuscles.isNotEmpty) {
    return 'Your focus: ${_names(analysis.confirmedMuscles).join(', ')}';
  }
  final suggested = [for (final p in analysis.result.priorities) p.muscle];
  return 'Focus suggested: ${_names(suggested).join(', ')}';
}

/// The latest check on the photo card; opens its result.
class PhysiqueSummaryRow extends StatelessWidget {
  const PhysiqueSummaryRow({
    required this.analysis,
    required this.onOpen,
    this.now,
    super.key,
  });

  final PhysiqueAnalysis analysis;
  final VoidCallback onOpen;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    return Pressable(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xs),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.sparkles,
                size: 18,
                color: colors.accentSignalInk,
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      physiqueFocusSummary(analysis),
                      style: theme.titleSmall,
                    ),
                    Text(
                      'Physique check · '
                      '${friendlyDate(analysis.createdAt, now: now)}',
                      style: theme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Phase { loading, consent, running, result, failed, saved }

/// The whole physique check in one sheet: the AI notice when it is not
/// granted, the running check, the result with focus selection, and the
/// saved focus. Errors stay inline because snackbars sit behind sheets.
class PhysiqueCheckSheet extends StatefulWidget {
  const PhysiqueCheckSheet({
    required this.repository,
    this.photoSetId,
    this.analysis,
    super.key,
  }) : assert(photoSetId != null || analysis != null);

  final PhysiqueCheckRepository repository;

  /// The complete set to check; the sheet starts a new check when set.
  final String? photoSetId;

  /// A stored check to open instead of starting one.
  final PhysiqueAnalysis? analysis;

  @override
  State<PhysiqueCheckSheet> createState() => _PhysiqueCheckSheetState();
}

class _PhysiqueCheckSheetState extends State<PhysiqueCheckSheet> {
  late _Phase _phase;
  PhotoAiNotice? _notice;
  PhysiqueAnalysis? _analysis;
  PhysiqueCheckError? _error;
  String? _inlineError;
  final List<String> _selected = [];
  bool _limitHint = false;
  bool _busy = false;
  bool _withdrawn = false;
  List<String> _saved = const [];

  PhysiqueCheckRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    final analysis = widget.analysis;
    if (widget.photoSetId == null && analysis != null) {
      _analysis = analysis;
      _selected.addAll(analysis.confirmedMuscles.take(maxFocusMuscles));
      _phase = _Phase.result;
      _loadNoticeForWithdraw();
    } else {
      _phase = _Phase.loading;
      _start();
    }
  }

  /// A stored result offers "Turn off photo checks" only while granted.
  Future<void> _loadNoticeForWithdraw() async {
    try {
      final notice = await _repository.loadNotice();
      if (mounted) setState(() => _notice = notice);
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.loading;
      _inlineError = null;
    });
    final PhotoAiNotice notice;
    try {
      notice = await _repository.loadNotice();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) _fail(PhysiqueCheckError.failed);
      return;
    }
    if (!mounted) return;
    _notice = notice;
    if (notice.granted) {
      await _run();
    } else {
      setState(() => _phase = _Phase.consent);
    }
  }

  Future<void> _agree() async {
    final notice = _notice;
    if (notice == null) return;
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await _repository.recordConsent(
        noticeVersion: notice.version,
        granted: true,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _inlineError =
              'Your choice was not saved. Check the connection and try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    _notice = notice.withGranted(true);
    _withdrawn = false;
    _busy = false;
    await _run();
  }

  Future<void> _run() async {
    final setId = widget.photoSetId;
    if (setId == null) return;
    setState(() {
      _phase = _Phase.running;
      _inlineError = null;
    });
    try {
      final analysis = await _repository.check(setId);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _selected.clear();
        _limitHint = false;
        _phase = _Phase.result;
      });
    } on PhysiqueCheckException catch (e) {
      if (!mounted) return;
      if (e.error == PhysiqueCheckError.consentRequired) {
        await _askAgain();
      } else {
        _fail(e.error);
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) _fail(PhysiqueCheckError.failed);
    }
  }

  /// The server no longer has a grant for the current notice (a new version,
  /// or a withdrawal elsewhere): show the notice it holds now.
  Future<void> _askAgain() async {
    try {
      final notice = await _repository.loadNotice();
      if (!mounted) return;
      setState(() {
        _notice = notice.withGranted(false);
        _phase = _Phase.consent;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) _fail(PhysiqueCheckError.failed);
    }
  }

  void _fail(PhysiqueCheckError error) => setState(() {
    _error = error;
    _phase = _Phase.failed;
  });

  void _toggle(String muscle) => setState(() {
    if (_selected.remove(muscle)) {
      _limitHint = false;
    } else if (_selected.length >= maxFocusMuscles) {
      _limitHint = true;
    } else {
      _selected.add(muscle);
      _limitHint = false;
    }
  });

  Future<void> _useAsFocus() async {
    final analysis = _analysis;
    if (analysis == null || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final saved = await _repository.setPriorityMuscles(
        List.of(_selected),
        analysisId: analysis.id,
      );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _busy = false;
        _phase = _Phase.saved;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _inlineError = 'Your focus was not saved. Try again.';
        });
      }
    }
  }

  Future<void> _withdraw() async {
    final notice = _notice;
    if (notice == null) return;
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await _repository.recordConsent(
        noticeVersion: notice.version,
        granted: false,
      );
      if (!mounted) return;
      setState(() {
        _notice = notice.withGranted(false);
        _withdrawn = true;
        _busy = false;
      });
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _inlineError =
              'Your choice was not saved. Check the connection and try again.';
        });
      }
    }
  }

  /// Shown in an untitled sheet with `scrollable: false`: each phase draws
  /// its own heading, and the sheet scrolls its body itself.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(top: TracendSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (_phase) {
        _Phase.loading => const [_Waiting()],
        _Phase.consent => _consent(context),
        _Phase.running => const [
          _Waiting(
            title: 'Checking your photos…',
            detail: 'Usually under 30 seconds.',
          ),
        ],
        _Phase.result => _result(context),
        _Phase.failed => _failed(context),
        _Phase.saved => _savedFocus(context),
      },
    ),
  );

  List<Widget> _consent(BuildContext context) => [
    AiNoticePanel(
      title: 'Check your photos with AI?',
      notice: _notice,
      agreeLabel: 'Agree and check',
      busy: _busy,
      error: _inlineError,
      onAgree: _agree,
      onDecline: () => Navigator.of(context).pop(),
    ),
  ];

  List<Widget> _result(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final result = _analysis!.result;
    return [
      Text('Physique check', style: theme.headlineSmall),
      const SizedBox(height: TracendSpacing.xxs),
      Text('AI visual estimate, not a measurement.', style: theme.titleSmall),
      const SizedBox(height: TracendSpacing.xxs),
      Text(
        'Muscles that could use more work compared with the rest of your '
        'build. Pick up to two as your focus.',
        style: theme.bodyMedium,
      ),
      const SizedBox(height: TracendSpacing.md),
      TracendGroupedList(
        children: [
          for (final priority in result.priorities)
            _PriorityRow(
              priority: priority,
              selected: _selected.contains(priority.muscle),
              onTap: _busy ? null : () => _toggle(priority.muscle),
            ),
        ],
      ),
      if (_limitHint) ...[
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Pick at most two',
          style: theme.bodyMedium?.copyWith(color: colors.stateAttention),
        ),
      ],
      if (result.observations.isNotEmpty)
        _Notes(
          title: 'What the check saw',
          icon: CupertinoIcons.eye,
          lines: result.observations,
        ),
      if (result.photoIssues.isNotEmpty)
        _Notes(
          title: 'For a clearer next check',
          icon: CupertinoIcons.camera,
          lines: [
            for (final issue in result.photoIssues)
              physiquePhotoIssueTips[issue]!,
          ],
        ),
      if (result.limitations.isNotEmpty) ...[
        const SizedBox(height: TracendSpacing.md),
        Text(
          result.limitations,
          style: theme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
      const SizedBox(height: TracendSpacing.lg),
      ..._inlineErrorRow(context),
      FilledButton(
        onPressed: _busy || _selected.isEmpty ? null : _useAsFocus,
        child: const Text('Use as my focus'),
      ),
      const SizedBox(height: TracendSpacing.xs),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Not now'),
      ),
      if (_withdrawn)
        Padding(
          padding: const EdgeInsets.only(top: TracendSpacing.xs),
          child: Text(
            'Photo checks are off. The next check asks you first.',
            textAlign: TextAlign.center,
            style: theme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        )
      else if (_notice?.granted == true)
        TextButton(
          onPressed: _busy ? null : _withdraw,
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          child: const Text('Turn off photo checks'),
        ),
    ];
  }

  List<Widget> _failed(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final error = _error ?? PhysiqueCheckError.failed;
    return [
      Text('Physique check', style: theme.headlineSmall),
      const SizedBox(height: TracendSpacing.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 18,
            color: colors.stateAttention,
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(child: Text(error.message, style: theme.bodyLarge)),
        ],
      ),
      const SizedBox(height: TracendSpacing.lg),
      if (error.retryable && widget.photoSetId != null) ...[
        FilledButton(
          onPressed: _notice == null ? _start : _run,
          child: const Text('Try again'),
        ),
        const SizedBox(height: TracendSpacing.xs),
      ],
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ];
  }

  List<Widget> _savedFocus(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    return [
      Icon(
        CupertinoIcons.checkmark_circle_fill,
        size: 40,
        color: colors.stateStable,
      ),
      const SizedBox(height: TracendSpacing.sm),
      Text(
        'Your focus is now ${_muscleList(_saved)}. The Coach uses it now; '
        'your plan uses it at its next review.',
        textAlign: TextAlign.center,
        style: theme.bodyLarge,
      ),
      const SizedBox(height: TracendSpacing.lg),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    ];
  }

  List<Widget> _inlineErrorRow(BuildContext context) {
    final message = _inlineError;
    if (message == null) return const [];
    return [
      Text(message, style: TextStyle(color: context.tracendColors.stateDanger)),
      const SizedBox(height: TracendSpacing.sm),
    ];
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({this.title, this.detail});

  final String? title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xl),
      child: Column(
        children: [
          TracendLoader(size: 36, semanticLabel: title ?? 'Loading'),
          if (title != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Text(title!, textAlign: TextAlign.center, style: theme.titleMedium),
          ],
          if (detail != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(detail!, textAlign: TextAlign.center, style: theme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// One suggested muscle with a checkbox; the whole row toggles it.
class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final PhysiquePriority priority;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final confidence = _confidenceLabels[priority.confidence]!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: TracendListRow(
        title: physiqueMuscleLabels[priority.muscle]!,
        subtitle: priority.reason.isEmpty
            ? confidence
            : '$confidence · ${priority.reason}',
        leading: Checkbox(
          value: selected,
          onChanged: onTap == null ? null : (_) => onTap!(),
        ),
      ),
    );
  }
}

/// A short titled list of observations or photo tips.
class _Notes extends StatelessWidget {
  const _Notes({required this.title, required this.icon, required this.lines});

  final String title;
  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleSmall),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 16, color: colors.textSecondary),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(child: Text(line, style: theme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
