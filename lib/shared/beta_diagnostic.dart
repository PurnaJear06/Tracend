import 'package:flutter/widgets.dart';

/// The code of the latest failure the athlete was shown a beta diagnostic
/// for, kept in memory only (never stored or sent) so that "Send feedback" can
/// put it in the email the athlete writes. A code names a failure ("HTTP 502",
/// "provider_response_invalid"); it holds no health value and none of the
/// athlete's words.
///
/// It is set where a failure is produced ([note]), not where a diagnostic line
/// is drawn, so a line that is rebuilt or shown again never replaces a newer
/// failure's code. The one exception is [BetaDiagnosticMark], for errors that
/// are only known once their line is on screen.
class LatestBetaDiagnostic {
  const LatestBetaDiagnostic._();

  static String? code;

  /// Remembers the code of a diagnostic [line] when a failure produces it.
  static void note(String? line) {
    final noted = line == null ? null : betaDiagnosticCode(line);
    if (noted != null) code = noted;
  }
}

/// The code at the front of a diagnostic line: "HTTP 502" from
/// "Beta diagnostic: HTTP 502", or "provider_response_invalid" from
/// "Beta diagnostic: provider_response_invalid · first attempt: …". The
/// detail after the first " · " is left out. Null when there is no code, and
/// for any text without the "Beta diagnostic" prefix, so raw exception text
/// never reaches the feedback email.
String? betaDiagnosticCode(String line) {
  final prefix = RegExp(r'^Beta diagnostic\s*[:·]\s*').firstMatch(line);
  if (prefix == null) return null;
  final code = line.substring(prefix.end).split(' · ').first.trim();
  if (code.isEmpty) return null;
  return code.length > 80 ? code.substring(0, 80) : code;
}

/// Wraps a beta diagnostic that is known only once it is drawn (a screen's
/// load error) and remembers its [code] as the latest one when it first
/// appears. It draws only its [child].
class BetaDiagnosticMark extends StatefulWidget {
  const BetaDiagnosticMark({
    required this.code,
    required this.child,
    super.key,
  });

  final String? code;
  final Widget child;

  @override
  State<BetaDiagnosticMark> createState() => _BetaDiagnosticMarkState();
}

class _BetaDiagnosticMarkState extends State<BetaDiagnosticMark> {
  @override
  void initState() {
    super.initState();
    _remember();
  }

  @override
  void didUpdateWidget(BetaDiagnosticMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _remember();
  }

  void _remember() {
    final code = widget.code;
    if (code != null) LatestBetaDiagnostic.code = code;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
