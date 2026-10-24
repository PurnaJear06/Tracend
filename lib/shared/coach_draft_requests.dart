import 'package:flutter/foundation.dart';

/// Hands a question from another screen to the Coach composer. The shell owns
/// one: a screen calls [request] and the shell opens Coach, which takes the
/// text with [take] and puts it in the box. Nothing is sent: the athlete reads
/// it, changes it if they like and sends it themselves.
class CoachDraftRequests extends ChangeNotifier {
  String? _pending;

  /// Leaves [text] for Coach to put in its composer.
  void request(String text) {
    _pending = text;
    notifyListeners();
  }

  /// The waiting question, once; null when there is none.
  String? take() {
    final text = _pending;
    _pending = null;
    return text;
  }
}
