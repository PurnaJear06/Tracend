import 'package:flutter/material.dart';

/// Text that truncates at [maxLines] and exposes a real expansion control
/// when the content exceeds that limit (plan §6.2).
///
/// Short content renders plainly — no dead "show more" affordance.
class ExpandableText extends StatefulWidget {
  const ExpandableText({
    required this.text,
    this.maxLines = 6,
    this.style,
    this.expandLabel = 'Show more',
    this.collapseLabel = 'Show less',
    super.key,
  });

  final String text;
  final int maxLines;
  final TextStyle? style;
  final String expandLabel;
  final String collapseLabel;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).textTheme.bodyLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflows)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? widget.collapseLabel : widget.expandLabel,
                ),
              ),
          ],
        );
      },
    );
  }
}
