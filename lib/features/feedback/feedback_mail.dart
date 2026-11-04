import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/beta_diagnostic.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where beta testers send feedback and bug reports.
const supportEmail = 'tracend.train@gmail.com';

/// The app's version name and build number, such as 1.1.0 and 920.
typedef AppVersion = ({String version, String build});

typedef AppVersionReader = Future<AppVersion?> Function();

/// Opens a mail composer for [mailto]; false when this phone has none.
typedef MailLauncher = Future<bool> Function(Uri mailto);

Future<AppVersion?> readAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: info.buildNumber);
  } catch (e) {
    logNonCritical(e, 'app version not read');
    return null;
  }
}

Future<bool> launchMail(Uri mailto) async {
  try {
    return await launchUrl(mailto);
  } catch (e) {
    logNonCritical(e, 'mail not opened');
    return false;
  }
}

/// What the email says about the app, and nothing else: the version and
/// build, and the last beta diagnostic code the athlete was shown. No health
/// value, no email address and no account id; whatever else the email holds
/// is what the athlete types.
List<String> feedbackDetails({AppVersion? version, String? diagnosticCode}) => [
  if (version != null) 'Tracend ${version.version} (${version.build})',
  if (diagnosticCode != null) 'Last problem code: $diagnosticCode',
];

/// The mailto link for "Send feedback": a subject, room for the athlete to
/// write above a line, and the [feedbackDetails] under it. Spaces are %20,
/// not +, which mail apps would show as written.
Uri feedbackMailUri({AppVersion? version, String? diagnosticCode}) {
  final body = [
    '',
    '',
    '(Write your feedback above this line.)',
    ...feedbackDetails(version: version, diagnosticCode: diagnosticCode),
  ].join('\n');
  final query =
      'subject=${Uri.encodeComponent('Tracend beta feedback')}'
      '&body=${Uri.encodeComponent(body)}';
  return Uri.parse('mailto:$supportEmail?$query');
}

/// Opens the mail composer addressed to [supportEmail], with the app version
/// and the last diagnostic code filled in. When the phone has no mail app set
/// up, a sheet shows the address to copy.
Future<void> sendFeedback(
  BuildContext context, {
  MailLauncher launch = launchMail,
  AppVersionReader readVersion = readAppVersion,
}) async {
  final version = await readVersion();
  final code = LatestBetaDiagnostic.code;
  final opened = await launch(
    feedbackMailUri(version: version, diagnosticCode: code),
  );
  if (opened || !context.mounted) return;
  await showTracendSheet<void>(
    context,
    title: 'Send feedback',
    builder: (_) => FeedbackAddressSheet(
      details: feedbackDetails(version: version, diagnosticCode: code),
    ),
  );
}

/// Shown when no mail app is set up: the address as selectable text with a
/// Copy button, and the details to mention.
class FeedbackAddressSheet extends StatelessWidget {
  const FeedbackAddressSheet({required this.details, super.key});

  final List<String> details;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (context.mounted) TracendToast.show(context, 'Address copied');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'There is no mail app set up on this iPhone. Email your feedback or '
          'bug report to this address from any mail account.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.sm),
        SelectableText(supportEmail, style: textTheme.titleMedium),
        if (details.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.sm),
          Text('Please mention:', style: textTheme.bodyMedium),
          SelectableText(details.join('\n'), style: textTheme.bodyMedium),
        ],
        const SizedBox(height: TracendSpacing.md),
        FilledButton(
          onPressed: () => _copy(context),
          child: const Text('Copy address'),
        ),
      ],
    );
  }
}
