import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Stylized section divider (Stitch `today.html`): hairline rules fading out
/// from a centered label-caps title.
class PrecisionDivider extends StatelessWidget {
  const PrecisionDivider({this.label = 'PRECISION READOUTS', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TracendSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, colors.borderHairline],
                ),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TracendSpacing.md,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TracendTheme.labelCaps(
                  context,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.borderHairline, Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
