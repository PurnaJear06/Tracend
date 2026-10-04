import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';

/// The morning check-in gate (owner, 2026-10-04): until today's check-in is
/// saved, the tab bar gives way to one bar, "Check in to start your day".
/// Saving it, or "Not today", brings the tab bar back for the rest of the
/// day. The plan never locks: "Not today" always lets the athlete through.
///
/// Today owns the state and the actions; the shell reads [required] to
/// choose its bottom bar.
class CheckInGate extends ChangeNotifier {
  bool _required = false;
  VoidCallback? _onCheckIn;
  VoidCallback? _onSkip;

  /// True while today's check-in is missing and was not put off.
  bool get required => _required;

  void update({
    required bool required,
    VoidCallback? onCheckIn,
    VoidCallback? onSkip,
  }) {
    _onCheckIn = onCheckIn;
    _onSkip = onSkip;
    if (_required == required) return;
    _required = required;
    notifyListeners();
  }

  void checkIn() => _onCheckIn?.call();
  void skip() => _onSkip?.call();
}

/// The gate's bar: a lime pill with an arrow, and "Not today" under it.
class CheckInGateBar extends StatelessWidget {
  const CheckInGateBar({
    required this.onCheckIn,
    required this.onSkip,
    this.floating = true,
    super.key,
  });

  final VoidCallback onCheckIn;
  final VoidCallback onSkip;

  /// True in the shell's bottom slot; false when shown inside Today.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final pill = Pressable(
      onTap: onCheckIn,
      pressedScale: 0.98,
      semanticLabel: 'Check in to start your day. About a minute',
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsetsDirectional.fromSTEB(22, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.accentSignal,
          borderRadius: BorderRadius.circular(TracendRadii.pill),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: colors.accentSignal.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Check in to start your day',
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.onAccentSignal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'About a minute · sharpens today’s call',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onAccentSignal.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.onAccentSignal,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.arrow_right,
                size: 20,
                color: colors.accentSignal,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: floating
          ? EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 4 : 10)
          : EdgeInsets.zero,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pill,
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Not today',
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
