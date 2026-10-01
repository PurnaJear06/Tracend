import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Rows of one kind share a single surface with hairline dividers
/// (DESIGN_SYSTEM.md §4, grouped lists). Use this instead of a card per row.
class TracendGroupedList extends StatelessWidget {
  const TracendGroupedList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xxs),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: TracendSpacing.md,
                endIndent: TracendSpacing.md,
                color: colors.borderHairline,
              ),
          ],
        ],
      ),
    );
  }
}

/// One row inside a [TracendGroupedList]. At least 52pt tall; shows a
/// chevron only when it is tappable, so no row looks interactive when it
/// is not.
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
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.md,
          vertical: TracendSpacing.sm,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: TracendSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
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
                size: 14,
                color: colors.textSecondary,
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
        borderRadius: BorderRadius.circular(TracendRadii.control),
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

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.tracendColors.textSecondary;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TracendRadii.control),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}
