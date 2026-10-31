import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// The referral for [route], in a sheet that cannot be missed. It has no
/// training choice: "Got it" only closes it.
///
/// For the two routes that need medical attention the same day (`urgent` and
/// `clinician_today`, and any route this build does not know) the sheet
/// cannot be swiped, tapped or closed away: the athlete acknowledges it with
/// "Got it". [extraLines] are fixed sentences shown under the body, such as
/// the line for pain that has lasted two weeks.
Future<void> showSafetyReferralSheet(
  BuildContext context,
  String route, {
  List<String> extraLines = const [],
}) {
  final words = safetyWords(route);
  final mustAcknowledge = routeNeedsAcknowledgement(route);
  return showTracendSheet<void>(
    context,
    title: words.title,
    isDismissible: !mustAcknowledge,
    enableDrag: !mustAcknowledge,
    showCloseButton: !mustAcknowledge,
    builder: (sheetContext) => PopScope(
      canPop: !mustAcknowledge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(words.body, style: Theme.of(sheetContext).textTheme.bodyLarge),
          for (final line in extraLines) ...[
            const SizedBox(height: TracendSpacing.xs),
            Text(line, style: Theme.of(sheetContext).textTheme.bodyMedium),
          ],
          const SizedBox(height: TracendSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text(gotItLabel),
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
      ),
    ),
  );
}
