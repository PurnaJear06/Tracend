import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// postgrest-dart's `order(column, {ascending = false})` sorts descending when
/// the direction is left out, which once loaded every Coach conversation
/// newest-first. Every query order in lib/ must say which way it sorts.
void main() {
  test('every PostgREST .order( in lib/ states ascending: explicitly', () {
    final offenders = <String>[];
    var calls = 0;
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\.order\(').allMatches(source)) {
        calls++;
        final arguments = _arguments(source, match.end);
        if (!RegExp(r'\bascending\s*:').hasMatch(arguments)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(calls, greaterThan(0), reason: 'the scan found no .order( calls');
    expect(offenders, isEmpty, reason: 'add ascending: true or false to these');
  });
}

/// The text between the call's parentheses, starting just after the opening one.
String _arguments(String source, int start) {
  var depth = 1;
  var index = start;
  while (index < source.length && depth > 0) {
    final char = source[index];
    if (char == '(') depth++;
    if (char == ')') depth--;
    index++;
  }
  return source.substring(start, index - 1);
}
