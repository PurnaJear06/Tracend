import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';

/// "This week": workouts done of planned as a count and pips, then the
/// Training load row and the History row, each opening its sheet.
class WeekSummaryCard extends StatelessWidget {
  const WeekSummaryCard({
    required this.done,
    required this.planned,
    required this.loadLabel,
    required this.onLoadTap,
    this.historyLabel,
    this.onHistoryTap,
    super.key,
  });

  final int done;
  final int planned;
  final String loadLabel;
  final VoidCallback onLoadTap;

  /// For example "6 workouts in 4 weeks"; the row hides without history.
  final String? historyLabel;
  final VoidCallback? onHistoryTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final pips = done > planned ? done : planned;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '$done of $planned workouts done this week',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workouts', style: textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$done of $planned',
                          style: TextStyle(
                            fontFamily: TracendFonts.displayFamily,
                            fontSize: 26,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colors.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: '  done',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pips > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < pips; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: i < done
                                    ? colors.stateStable
                                    : colors.surfaceRaised,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
          _Separator(color: colors.borderHairline),
          _SummaryRow(
            title: 'Training load',
            value: loadLabel,
            onTap: onLoadTap,
          ),
          if (historyLabel != null && onHistoryTap != null) ...[
            _Separator(color: colors.borderHairline),
            _SummaryRow(
              title: 'History',
              value: historyLabel!,
              onTap: onHistoryTap!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 16),
    child: Divider(height: 1, thickness: 1, color: color),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title: $value',
      borderRadius: BorderRadius.circular(TracendRadii.card),
      pressedScale: 0.99,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: textTheme.titleSmall),
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
