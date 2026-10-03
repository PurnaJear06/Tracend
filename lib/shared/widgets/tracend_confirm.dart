import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// One choice in [showTracendActionSheet].
@immutable
class TracendSheetAction<T> {
  const TracendSheetAction({
    required this.label,
    required this.value,
    this.destructive = false,
    this.isDefault = false,
  });

  final String label;

  /// What [showTracendActionSheet] completes with when this is chosen.
  final T value;

  /// Deletes or discards something. Rendered in the danger color.
  final bool destructive;

  /// The expected choice. Rendered in semibold.
  final bool isDefault;
}

/// An iOS action sheet in Tracend tokens (DESIGN_SYSTEM.md §5.1, confirm):
/// choices rise from the bottom with a separate Cancel. Completes with the
/// chosen action's value, or null on Cancel or a tap outside.
///
/// Use it for two or more related choices, such as "Leave this workout?"
/// with Save and Discard. A destructive choice plays the warning haptic.
Future<T?> showTracendActionSheet<T>(
  BuildContext context, {
  required List<TracendSheetAction<T>> actions,
  String? title,
  String? message,
  String cancelLabel = 'Cancel',
}) {
  assert(actions.isNotEmpty);
  final colors = context.tracendColors;
  if (actions.any((action) => action.destructive)) TracendHaptics.warning();
  return showCupertinoModalPopup<T>(
    context: context,
    barrierColor: colors.scrim,
    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
    builder: (popupContext) {
      final text = _DialogText(popupContext);
      return CupertinoActionSheet(
        title: title == null ? null : Text(title, style: text.sheetTitle),
        message: message == null
            ? null
            : Text(message, style: text.sheetMessage),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: action.destructive,
              isDefaultAction: action.isDefault,
              onPressed: () => Navigator.of(popupContext).pop(action.value),
              child: Text(
                action.label,
                style: text.action(
                  destructive: action.destructive,
                  emphasized: action.isDefault,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text(cancelLabel, style: text.action(emphasized: true)),
        ),
      );
    },
  );
}

/// An iOS alert in Tracend tokens that asks before a consequential step and
/// completes with true only when [confirmLabel] is tapped.
///
/// With [destructive] the confirm button uses the danger color, Cancel
/// becomes the bold default (so the safe choice is the obvious one) and the
/// warning haptic plays as the alert appears.
Future<bool> showTracendConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  if (destructive) unawaited(TracendHaptics.warning());
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final text = _DialogText(dialogContext);
      return CupertinoAlertDialog(
        title: Text(title, style: text.alertTitle),
        content: message == null
            ? null
            : Text(message, style: text.alertMessage),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: text.action(emphasized: destructive),
            ),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: text.action(
                destructive: destructive,
                emphasized: !destructive,
              ),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Token text styles for Cupertino alerts and action sheets. Body type is the
/// system font, as on iOS; only the colors and weights come from Tracend.
class _DialogText {
  _DialogText(BuildContext context)
    : _colors = context.tracendColors,
      _base = Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.3);

  final TracendColors _colors;
  final TextStyle _base;

  TextStyle get sheetTitle => _base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: _colors.textSecondary,
  );

  TextStyle get sheetMessage =>
      _base.copyWith(fontSize: 13, color: _colors.textSecondary);

  TextStyle get alertTitle => _base.copyWith(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: _colors.textPrimary,
  );

  TextStyle get alertMessage =>
      _base.copyWith(fontSize: 13, color: _colors.textPrimary);

  TextStyle action({bool destructive = false, bool emphasized = false}) =>
      _base.copyWith(
        fontSize: 17,
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
        color: destructive ? _colors.stateDanger : _colors.textPrimary,
      );
}
