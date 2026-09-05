import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

class TracendScrollView extends StatelessWidget {
  const TracendScrollView({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final gutter = size.width < 375 ? TracendSpacing.md : TracendSpacing.gutter;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            key: PageStorageKey(title),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  TracendSpacing.md,
                  gutter,
                  176,
                ),
                sliver: SliverList.list(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: TracendSpacing.xxs),
                                Text(
                                  subtitle!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                    const SizedBox(height: TracendSpacing.lg),
                    ...children,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TracendCard extends StatelessWidget {
  const TracendCard({
    required this.child,
    this.padding = const EdgeInsets.all(TracendSpacing.md),
    this.radius = TracendRadii.card,
    this.raised = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: raised ? colors.surfaceRaised : colors.surface,
          border: Border.all(
            color: raised
                ? colors.borderSubtle.withValues(alpha: 0.72)
                : colors.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: raised
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.20
                          : 0.055,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class TracendPill extends StatelessWidget {
  const TracendPill({
    required this.label,
    this.icon,
    this.color,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final accent = color ?? colors.actionPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? TracendSpacing.xs : TracendSpacing.sm,
          vertical: compact ? TracendSpacing.xxs : TracendSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 13 : 15, color: accent),
              const SizedBox(width: TracendSpacing.xxs),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: accent, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: TracendSpacing.lg,
        bottom: TracendSpacing.sm,
      ),
      // labelCaps restyle (owner-approved 2026-09-04, DESIGN_SYSTEM §3.2:
      // "every caps label renders through TracendTheme.labelCaps") — text
      // content unchanged, style-only, so all tabs inherit the standard.
      child: Text(label.toUpperCase(), style: TracendTheme.labelCaps(context)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.icon, super.key});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.stateStable.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: TracendSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.stateStable),
            const SizedBox(width: TracendSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.stateStable),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricRow extends StatelessWidget {
  const MetricRow({
    required this.label,
    required this.value,
    required this.detail,
    this.accent,
    super.key,
  });

  final String label;
  final String value;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: accent ?? colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Text(detail, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class MetricStrip extends StatelessWidget {
  const MetricStrip({required this.items, super.key});

  final List<MetricStripItem> items;

  @override
  Widget build(BuildContext context) {
    final vertical = MediaQuery.textScalerOf(context).scale(13) > 17;
    if (vertical) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _MetricStripCell(item: items[i]),
            if (i < items.length - 1)
              Divider(
                height: TracendSpacing.lg,
                color: context.tracendColors.borderSubtle,
              ),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: _MetricStripCell(item: items[i])),
          if (i < items.length - 1)
            Container(
              width: 1,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: TracendSpacing.sm),
              color: context.tracendColors.borderSubtle,
            ),
        ],
      ],
    );
  }
}

class MetricStripItem {
  const MetricStripItem({
    required this.label,
    required this.value,
    required this.detail,
    this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color? color;
}

class _MetricStripCell extends StatelessWidget {
  const _MetricStripCell({required this.item});

  final MetricStripItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          item.value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: item.color ?? colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Text(item.detail, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
