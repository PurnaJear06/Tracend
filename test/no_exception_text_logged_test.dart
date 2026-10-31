import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An exception's text can carry health or meal values (a Postgres error
/// names the failing row). The app logs failures with `logNonCritical`, which
/// prints the type and code only, so no `debugPrint` may interpolate one.
void main() {
  test('no debugPrint interpolates an exception', () {
    final pattern = RegExp(
      r'debugPrint\([^;]*\$\{?(?:e|error|err|exception|failure)\b',
      dotAll: true,
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (pattern.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });
}
