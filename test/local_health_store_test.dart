import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/local_health_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the store', () {
    const store = LocalHealthStore();

    test('keeps text and lists of text by key, and forgets them', () async {
      await store.setString('daily_check_in_queue.user-1', '{"a":1}');
      await store.setStringList('safety_acknowledged', ['2026-10-02:urgent']);

      expect(await store.getString('daily_check_in_queue.user-1'), '{"a":1}');
      expect(await store.getStringList('safety_acknowledged'), [
        '2026-10-02:urgent',
      ]);
      expect(await store.getString('missing'), isNull);
      expect(await store.getStringList('missing'), isNull);

      await store.remove('daily_check_in_queue.user-1');
      expect(await store.getString('daily_check_in_queue.user-1'), isNull);
      // Removing what is not there is not an error.
      await store.remove('daily_check_in_queue.user-1');
    });

    test('a value that is not a list of text is not a list', () async {
      await store.setString('a', 'plain');
      await store.setString('b', '{"k":1}');
      await store.setString('c', '[1,2]');

      expect(await store.getStringList('a'), isNull);
      expect(await store.getStringList('b'), isNull);
      expect(await store.getStringList('c'), isNull);
    });

    test('lists every key as it was written, however odd', () async {
      const keys = {
        'workout_draft_11111111-1111-4111-8111-111111111111_w1',
        'safety_acknowledged.athlete-1',
        '2026-10-02:urgent/with space',
        '.hidden',
        'ünïcode',
      };
      for (final key in keys) {
        await store.setString(key, 'x');
      }

      expect(await store.getKeys(), keys);
      for (final key in keys) {
        expect(await store.getString(key), 'x', reason: key);
      }
    });

    test('removeAll removes the keys named and no other', () async {
      await store.setString('a', '1');
      await store.setString('b', '2');
      await store.setString('c', '3');

      await store.removeAll({'a', 'c', 'never-kept'});

      expect(await store.getKeys(), {'b'});
    });

    test('a file that is not the store\'s is not a key', () async {
      final files = LocalHealthFiles.instance;
      await files.write('stray.tmp', 'x');
      await store.setString('kept', '1');

      expect(await store.getKeys(), {'kept'});
    });
  });

  group('the files on the phone', () {
    late Directory folder;
    late List<MethodCall> calls;
    var directoryAnswers = <Object>[];

    setUp(() {
      folder = Directory.systemTemp.createTempSync('health-cache-');
      calls = [];
      directoryAnswers = [folder.path];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tracend/local_health_store'),
            (call) async {
              calls.add(call);
              switch (call.method) {
                case 'directory':
                  final answer = directoryAnswers.removeAt(0);
                  if (answer is String) return answer;
                  throw PlatformException(code: 'unavailable');
                case 'write':
                  final arguments = call.arguments as Map;
                  File(
                    '${folder.path}/${arguments['name']}',
                  ).writeAsStringSync(arguments['contents'] as String);
                  return true;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tracend/local_health_store'),
            null,
          );
      folder.deleteSync(recursive: true);
    });

    test('are written by the native side and read, listed and removed '
        'here', () async {
      final files = NativeLocalHealthFiles();

      await files.write('a.hc', 'one');
      await files.write('b.hc', 'two');

      expect(await files.read('a.hc'), 'one');
      expect(await files.read('missing.hc'), isNull);
      expect(await files.names(), unorderedEquals(['a.hc', 'b.hc']));
      // Every write goes through the channel, which sets the protection.
      expect(
        calls
            .where((call) => call.method == 'write')
            .map((call) => (call.arguments as Map)['name']),
        ['a.hc', 'b.hc'],
      );

      await files.delete('a.hc');
      await files.delete('a.hc');
      expect(await files.names(), ['b.hc']);
    });

    test('keep odd keys apart in a real folder, and read them back', () async {
      final store = LocalHealthStore(files: NativeLocalHealthFiles());
      final keys = {
        'workout_draft_11111111-1111-4111-8111-111111111111_w1',
        'safety_acknowledged.athlete-1',
        '2026-10-02:urgent/with space',
        'a%2Fb',
        '.hidden',
        'ünïcode 💪',
        'x' * 150,
      };
      for (final key in keys) {
        await store.setString(key, 'value of $key');
      }

      expect(await store.getKeys(), keys);
      for (final key in keys) {
        expect(await store.getString(key), 'value of $key', reason: key);
      }
      expect(
        folder.listSync().map((entity) => entity.uri.pathSegments.last),
        everyElement(isNot(contains('/'))),
      );
      await store.removeAll(keys);
      expect(await store.getKeys(), isEmpty);
      expect(folder.listSync(), isEmpty);
    });

    test('are not used when the folder cannot be prepared, and tried again '
        'next time', () async {
      final files = NativeLocalHealthFiles();
      directoryAnswers = [Object(), folder.path];

      await expectLater(files.write('a.hc', 'one'), throwsA(anything));
      expect(File('${folder.path}/a.hc').existsSync(), isFalse);

      await files.write('a.hc', 'one');
      expect(await files.read('a.hc'), 'one');
    });
  });
}
