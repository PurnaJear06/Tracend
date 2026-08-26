import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Coach chat composer (plan §6.2).
///
/// Disabled while sending, while no chat backend is configured, or while a
/// rate-limit cooldown is active. The cooldown countdown is real state from
/// the server `retry_after_seconds`, never fabricated.
class CoachComposer extends StatelessWidget {
  const CoachComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    this.cooldownRemaining,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final int? cooldownRemaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final cooldownActive = (cooldownRemaining ?? 0) > 0;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.canvas,
          border: Border(top: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.sm,
            TracendSpacing.gutter,
            TracendSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText: cooldownActive
                        ? 'Limit reached — retry in ${cooldownRemaining}s'
                        : 'Ask your Coach',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TracendRadii.control),
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              IconButton.filled(
                tooltip: 'Send message',
                onPressed: enabled ? onSend : null,
                icon: const Icon(CupertinoIcons.arrow_up),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
