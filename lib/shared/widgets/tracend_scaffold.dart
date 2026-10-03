import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// The page frame for top-level tabs (DESIGN_SYSTEM.md §5.1, large title).
///
/// The iOS large title scrolls with the content. Once it passes under the
/// status bar, a glass inline bar with the same title fades in; scrolling
/// back up fades it out. Pass [onRefresh] to add pull to refresh, which
/// should rerun the screen's existing reload.
class TracendScrollView extends StatefulWidget {
  const TracendScrollView({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.onRefresh,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  /// Called by pull to refresh; the spinner stays until the future completes.
  final Future<void> Function()? onRefresh;

  /// Height of the inline bar below the status bar.
  static const inlineBarHeight = 44.0;

  @override
  State<TracendScrollView> createState() => _TracendScrollViewState();
}

class _TracendScrollViewState extends State<TracendScrollView> {
  final _frameKey = GlobalKey();
  final _titleKey = GlobalKey();
  bool _collapsed = false;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    // A restored scroll offset can start the page already scrolled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCollapsed());
  }

  bool _handleScroll(ScrollNotification notification) {
    // Positions are read after the frame lays the new offset out; during the
    // notification they still describe the previous frame.
    if (notification.depth == 0 && !_checkScheduled) {
      _checkScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkScheduled = false;
        _updateCollapsed();
      });
    }
    return false;
  }

  void _updateCollapsed() {
    if (!mounted) return;
    final frame = _frameKey.currentContext?.findRenderObject() as RenderBox?;
    final title = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (frame == null || !frame.hasSize) return;
    // The bar takes over once most of the large title has slid under it.
    final threshold =
        MediaQuery.paddingOf(context).top +
        TracendScrollView.inlineBarHeight / 2;
    final bool collapsed;
    if (title == null || !title.attached || !title.hasSize) {
      // The header is built first, so a missing title has scrolled away.
      collapsed = true;
    } else {
      final titleBottom = title
          .localToGlobal(Offset(0, title.size.height), ancestor: frame)
          .dy;
      collapsed = titleBottom <= threshold;
    }
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final gutter = size.width < 375 ? TracendSpacing.md : TracendSpacing.gutter;
    final textTheme = Theme.of(context).textTheme;
    final onRefresh = widget.onRefresh;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                // One line that shrinks to fit, as iOS large titles do, so a
                // long word never breaks mid-word at large text sizes.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.title,
                    key: _titleKey,
                    maxLines: 1,
                    style: textTheme.displaySmall,
                  ),
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: TracendSpacing.xxs),
                Text(widget.subtitle!, style: textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: TracendSpacing.sm),
          widget.trailing!,
        ],
      ],
    );
    return Stack(
      key: _frameKey,
      children: [
        Padding(
          padding: EdgeInsets.only(top: safeTop),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScroll,
                  child: CustomScrollView(
                    key: PageStorageKey(widget.title),
                    // Content scrolls up under the status bar and the glass
                    // inline bar instead of being cut off at the safe area.
                    clipBehavior: Clip.none,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      if (onRefresh != null)
                        CupertinoSliverRefreshControl(onRefresh: onRefresh),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          TracendSpacing.xs,
                          gutter,
                          176,
                        ),
                        sliver: SliverList.list(
                          children: [
                            header,
                            const SizedBox(height: TracendSpacing.lg),
                            ...widget.children,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // The bar only repeats the title, so taps reach the content below.
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: TracendMotionScope.fade(context, TracendMotion.quick),
              child: _collapsed
                  ? _InlineTitleBar(
                      key: const ValueKey('inline-title'),
                      title: widget.title,
                      safeTop: safeTop,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineTitleBar extends StatelessWidget {
  const _InlineTitleBar({
    required this.title,
    required this.safeTop,
    super.key,
  });

  final String title;
  final double safeTop;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    // The large title stays the page's header for VoiceOver; this bar only
    // repeats it visually.
    return ExcludeSemantics(
      child: TracendGlass(
        borderRadius: 0,
        border: Border(bottom: BorderSide(color: colors.borderHairline)),
        child: SizedBox(
          height: safeTop + TracendScrollView.inlineBarHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              TracendSpacing.xl * 2,
              safeTop,
              TracendSpacing.xl * 2,
              0,
            ),
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.35),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A flat content card (DESIGN_SYSTEM.md §3.4): a `surface` fill, or the
/// `surfaceRaised` fill when [raised], with no border, gradient or shadow.
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
          borderRadius: BorderRadius.circular(radius),
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

/// A section title inside a page: sentence case, 20pt Archivo, with an
/// optional trailing [value] ("16 sets") or text action ("See all").
/// Write [label] as it should read; it is never uppercased.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.label, {
    this.value,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String label;

  /// Quiet trailing context, such as a count.
  final String? value;

  /// Optional trailing text action, such as "See all".
  final String? actionLabel;
  final VoidCallback? onAction;

  /// At large text sizes a trailing value or action would squeeze the
  /// label, so they move under it.
  bool _stacked(BuildContext context) =>
      (value != null || actionLabel != null) &&
      MediaQuery.textScalerOf(context).scale(1) > 1.3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: EdgeInsets.only(
        top: hasAction ? TracendSpacing.sm : TracendSpacing.lg,
        bottom: hasAction ? TracendSpacing.xxs : TracendSpacing.sm,
        left: 2,
        right: hasAction ? 0 : 2,
      ),
      child: _stacked(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(label, style: textTheme.titleLarge),
                ),
                if (value != null) Text(value!, style: textTheme.bodySmall),
                if (hasAction)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(label, style: textTheme.titleLarge),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: TracendSpacing.sm),
                  Text(value!, style: textTheme.bodySmall),
                ],
                if (hasAction) ...[
                  const SizedBox(width: TracendSpacing.xs),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: TracendSpacing.xs,
                      ),
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The meaning a [StatusChip] carries. Lime ([signal]) marks brand and
/// selection only; it never means "good".
enum StatusTone {
  /// Done, healthy, synced.
  good,

  /// Needs a look soon: pending, partial, a conflict to review.
  caution,

  /// Needs attention now: failed, below the floor.
  low,

  /// Information with no judgement.
  neutral,

  /// Brand and action signal: new, now, selected.
  signal,
}

/// A small status pill: a tone-colored icon on a tone wash, with the label
/// in primary text so it stays readable in every tone.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.icon,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final String label;
  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final (Color fill, Color iconColor) = switch (tone) {
      StatusTone.good => (colors.stateGoodTint, colors.stateStable),
      StatusTone.caution => (
        colors.accentAmber.withValues(alpha: 0.14),
        colors.accentAmber,
      ),
      StatusTone.low => (
        colors.stateAttention.withValues(alpha: 0.14),
        colors.stateAttention,
      ),
      StatusTone.neutral => (colors.surfaceRaised, colors.textSecondary),
      StatusTone.signal => (colors.accentSignalTint, colors.accentSignalInk),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textPrimary),
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
