import 'package:flutter/material.dart';
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
                  132,
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
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
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

class ComingSoonButton extends StatelessWidget {
  const ComingSoonButton({
    required this.label,
    required this.detail,
    this.icon,
    super.key,
  });

  final String label;
  final String detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: detail,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(icon ?? Icons.lock_outline, size: 18),
          label: Text('$label · planned'),
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

class MiniTrendChart extends StatelessWidget {
  const MiniTrendChart({
    required this.values,
    required this.label,
    this.height = 96,
    this.fill = true,
    super.key,
  });

  final List<double> values;
  final String label;
  final double height;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniTrendPainter(
              values: values,
              line: colors.actionPrimary,
              fill: fill ? colors.actionPrimary.withValues(alpha: 0.12) : null,
              grid: colors.borderSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTrendPainter extends CustomPainter {
  const _MiniTrendPainter({
    required this.values,
    required this.line,
    required this.grid,
    this.fill,
  });

  final List<double> values;
  final Color line;
  final Color grid;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = (maxValue - minValue).abs() < 0.001 ? 1 : maxValue - minValue;
    final dx = size.width / (values.length - 1);
    Offset point(int i) {
      final normalized = (values[i] - minValue) / range;
      return Offset(i * dx, size.height - (normalized * size.height));
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      final previous = point(i - 1);
      final current = point(i);
      final controlDx = (current.dx - previous.dx) / 2;
      path.cubicTo(
        previous.dx + controlDx,
        previous.dy,
        current.dx - controlDx,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    if (fill != null) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 3.5, Paint()..color = line);
      canvas.drawCircle(
        point(i),
        6,
        Paint()
          ..color = line.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid ||
      oldDelegate.fill != fill;
}
