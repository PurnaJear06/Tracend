import 'package:flutter/widgets.dart';

/// The latest beta diagnostic code the athlete was shown, kept in memory only
/// (never stored or sent) so that "Send feedback" can put it in the email the
/// athlete writes. A code names a failure ("HTTP 502", "provider_response_invalid");
/// it holds no health value and none of the athlete's words.
class LatestBetaDiagnostic {
  const LatestBetaDiagnostic._();

  static String? code;
}

/// The code at the front of a diagnostic line: "HTTP 502" from
/// "Beta diagnostic: HTTP 502", or "provider_response_invalid" from
/// "Beta diagnostic: provider_response_invalid · first attempt: …". The
/// detail after the first " · " is left out. Null when there is no code.
String? betaDiagnosticCode(String line) {
  final stripped = line.replaceFirst(RegExp(r'^Beta diagnostic\s*[:·]\s*'), '');
  final code = stripped.split(' · ').first.trim();
  if (code.isEmpty) return null;
  return code.length > 80 ? code.substring(0, 80) : code;
}

/// Wraps a shown beta diagnostic and remembers its [code] as the latest one
/// the athlete saw. It draws only its [child].
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
