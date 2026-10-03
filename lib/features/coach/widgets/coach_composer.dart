import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Coach chat composer (plan §6.2): a filled pill field with a round lime
/// send button, on a canvas band that clears the tab bar.
///
/// Disabled while sending, while no chat backend is configured, or while a
/// rate-limit cooldown is active. The cooldown countdown is real state from
/// the server `retry_after_seconds`, never fabricated. The send button turns
/// lime when there is something to send (an empty send does nothing); the
/// screen plays the light haptic as a message goes out.
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

  static const _sendSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final cooldownActive = (cooldownRemaining ?? 0) > 0;
    // The tab bar is drawn over the screen's bottom edge, and the padding
    // below says how tall it is. With the keyboard up the screen already
    // ends at the keyboard, so the composer sits right on it.
    final keyboardUp =
        MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
    final bottom = keyboardUp ? 0.0 : MediaQuery.paddingOf(context).bottom;
    const pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(TracendRadii.pill)),
      borderSide: BorderSide.none,
    );
    return ColoredBox(
      color: colors.canvas,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TracendSpacing.md,
          TracendSpacing.xs,
          TracendSpacing.md,
          TracendSpacing.xs + bottom,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                    style: textTheme.bodyLarge,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: cooldownActive
                          ? 'Limit reached. Try again in ${cooldownRemaining}s'
                          : 'Ask your Coach',
                      hintMaxLines: 1,
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                      border: pill,
                      enabledBorder: pill,
                      disabledBorder: pill,
                      focusedBorder: pill.copyWith(
                        borderSide: BorderSide(
                          color: colors.focusRing,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: TracendSpacing.xs),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => _SendButton(
                    enabled: enabled,
                    ready: value.text.trim().isNotEmpty,
                    onPressed: onSend,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.ready,
    required this.onPressed,
  });

  final bool enabled;

  /// There is text to send: the button turns lime.
  final bool ready;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return AnimatedContainer(
      duration: TracendMotionScope.fade(context, TracendMotion.quick),
      width: CoachComposer._sendSize,
      height: CoachComposer._sendSize,
      decoration: BoxDecoration(
        color: enabled && ready ? colors.accentSignal : colors.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: 'Send message',
        onPressed: enabled ? onPressed : null,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: ready ? colors.onAccentSignal : colors.textSecondary,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size.square(CoachComposer._sendSize),
        ),
        icon: const Icon(CupertinoIcons.arrow_up, size: 22),
      ),
    );
  }
}
