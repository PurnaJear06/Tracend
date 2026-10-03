import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Inset grouped list (DESIGN_SYSTEM.md §5.1): rows of one kind share a single
/// `surface` with hairline separators. A separator starts past the leading
/// icon of the row below it, as on iOS. Use this instead of a card per row.
class TracendGroupedList extends StatelessWidget {
  const TracendGroupedList({required this.children, super.key});

  final List<Widget> children;

  static double _indentBefore(Widget row) {
    if (row is TracendListRow && row.leading != null) {
      return TracendListRow.horizontalPadding +
          TracendRowIcon.size +
          TracendListRow.leadingGap;
    }
    return TracendListRow.horizontalPadding;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(TracendRadii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _indentBefore(children[i]),
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.borderHairline,
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row inside a [TracendGroupedList]. At least 60pt tall; shows a
/// chevron and a pressed fill only when it is tappable, so no row looks
/// interactive when it is not.
class TracendListRow extends StatelessWidget {
  const TracendListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Usually a [TracendRowIcon]; separators are inset to its width.
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const horizontalPadding = 14.0;
  static const leadingGap = TracendSpacing.sm;
  static const minHeight = 60.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: leadingGap),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: theme.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: TracendSpacing.sm),
              trailing!,
            ],
            if (onTap != null) ...[
              const SizedBox(width: TracendSpacing.xs),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? row
          : Semantics(label: semanticLabel, excludeSemantics: true, child: row);
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        onTap: onTap,
        highlightColor: colors.surfaceRaised,
        child: row,
      ),
    );
  }
}

/// Rounded leading glyph for a [TracendListRow].
class TracendRowIcon extends StatelessWidget {
  const TracendRowIcon({required this.icon, this.color, super.key});

  final IconData icon;
  final Color? color;

  static const size = 30.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.14) ?? colors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: color ?? colors.textSecondary),
    );
  }
}
