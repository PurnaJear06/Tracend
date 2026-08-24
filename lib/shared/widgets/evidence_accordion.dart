import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Collapsible evidence surface with correct collapse semantics
/// (plan §6.2, master-plan P1).
///
/// Behavior contract:
/// - The content height animates BEFORE the collapsed content is removed from
///   the tree. Collapsing reverses the height animation and only unmounts the
///   child once the animation is dismissed.
/// - The chevron rotates with the same animation controller.
/// - Motion uses the established [TracendMotion] tokens.
/// - When `MediaQuery.disableAnimationsOf(context)` is true (Reduce Motion on
///   the pinned Flutter SDK), expand/collapse is instant: the controller jumps
///   to its end value and collapsed content is unmounted immediately.
/// - The header is an accessible button that announces its expanded state.
class EvidenceAccordion extends StatefulWidget {
  const EvidenceAccordion({
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<EvidenceAccordion> createState() => _EvidenceAccordionState();
}

class _EvidenceAccordionState extends State<EvidenceAccordion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _height;
  late final Animation<double> _turns;
  late bool _expanded;
  late bool _contentMounted;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _contentMounted = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: TracendMotion.standard,
      value: _expanded ? 1 : 0,
    );
    _height = CurvedAnimation(parent: _controller, curve: TracendMotion.curve);
    _turns = Tween<double>(begin: 0, end: 0.5).animate(_height);
    _controller.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_expanded && _contentMounted) {
      if (mounted) setState(() => _contentMounted = false);
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_expanded;
    setState(() {
      _expanded = next;
      if (next) _contentMounted = true;
    });
    if (_reduceMotion) {
      _controller.value = next ? 1 : 0;
      if (!next && _contentMounted) setState(() => _contentMounted = false);
      return;
    }
    if (next) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: widget.title,
          container: true,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(TracendRadii.control),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: TracendSpacing.xs,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: TracendSpacing.sm),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ),
                      RotationTransition(
                        turns: _turns,
                        child: Icon(
                          CupertinoIcons.chevron_down,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_contentMounted)
          AnimatedBuilder(
            animation: _height,
            builder: (context, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _height.value,
                child: child,
              ),
            ),
            child: widget.child,
          ),
      ],
    );
  }
}
