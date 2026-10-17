import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/today_widget_snapshot.dart';

/// The snapshot the app writes for the widgets. `ios/Shared/
/// TodayWidgetSnapshot.swift` reads the same fixture in
/// `ios/RunnerTests/RunnerTests.swift`, so a change to the shape fails on
/// one side or the other until both agree. Change the shape only by adding
/// fields, and raise `schema_version` for anything else.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/contract/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Today widget snapshot v1', () {
    final brief = DailyBrief(
      localDate: '2026-10-18',
      workout: const {
        'name': 'Push day',
        'exercises': [
          {
            'order': 1,
            'name': 'Bench press',
            'set_count': 4,
            'rep_min': 6,
            'rep_max': 8,
            'target_load_kg': 82.5,
          },
          {
            'order': 2,
            'name': 'Overhead press',
            'set_count': 3,
            'rep_min': 8,
            'rep_max': 10,
            'target_load_kg': 45,
          },
        ],
      },
      todaySession: const TodaySession(
        state: 'in_progress',
        completedSets: {1: 2},
      ),
      nutrition: const {'calories': 1240, 'protein_g': 80},
      computed: ComputedMetrics.fromJson({
        'scores': {'recovery': 72},
      }),
    );

    TodayWidgetSnapshot build({required bool lockScreenNumbers}) =>
        TodayWidgetSnapshot.build(
          brief: brief,
          targets: const NutritionTargets(
            calories: 2400,
            protein: 160,
            carbohydrate: 280,
            fat: 70,
          ),
          checkedIn: true,
          lockScreenNumbers: lockScreenNumbers,
          now: DateTime.utc(2026, 10, 18, 7, 30),
        );

    test('the fixture is exactly what the app writes', () {
      expect(
        jsonDecode(jsonEncode(build(lockScreenNumbers: true).toJson())),
        _fixture('today_widget_snapshot_v1.json'),
      );
    });

    test('hidden Lock Screen numbers match the fixture without its lock', () {
      expect(jsonDecode(jsonEncode(build(lockScreenNumbers: false).toJson())), {
        ..._fixture('today_widget_snapshot_v1.json'),
        'lock': null,
      });
    });

    test('the shape is version 1 with a twelve hour stale limit', () {
      final fixture = _fixture('today_widget_snapshot_v1.json');
      expect(fixture['schema_version'], TodayWidgetSnapshot.schemaVersion);
      expect(fixture['stale_after_seconds'], 43200);
    });
  });

  group('tracend/home_widgets channel', () {
    final calls = <MethodCall>[];
    var pending = HomeWidgetTab.train.key as String?;

    setUp(() {
      calls.clear();
      pending = HomeWidgetTab.train.key;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(homeWidgetChannel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'write':
              case 'clear':
                return true;
              case 'takePendingTab':
                final tab = pending;
                pending = null;
                return tab;
            }
            throw MissingPluginException();
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(homeWidgetChannel, null);
    });

    test('write sends the snapshot JSON as `snapshot`', () async {
      await const MethodChannelHomeWidgetBridge().write('{"a":1}');

      expect(calls.single.method, 'write');
      expect(calls.single.arguments, {'snapshot': '{"a":1}'});
    });

    test('clear sends no arguments', () async {
      await const MethodChannelHomeWidgetBridge().clear();

      expect(calls.single.method, 'clear');
      expect(calls.single.arguments, isNull);
    });

    test('takePendingTab names the tab once', () async {
      const bridge = MethodChannelHomeWidgetBridge();

      expect(await bridge.takePendingTab(), HomeWidgetTab.train);
      expect(await bridge.takePendingTab(), isNull);
    });

    test('an unknown tab name is ignored', () async {
      pending = 'settings';
      expect(
        await const MethodChannelHomeWidgetBridge().takePendingTab(),
        isNull,
      );
    });

    test('a native error is swallowed, never thrown', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(homeWidgetChannel, (call) async {
            throw PlatformException(code: 'no_app_group');
          });
      const bridge = MethodChannelHomeWidgetBridge();

      await bridge.write('{}');
      expect(await bridge.takePendingTab(), isNull);
    });

    test('a missing native side is swallowed too', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(homeWidgetChannel, null);

      await const MethodChannelHomeWidgetBridge().clear();
    });

    test('iOS tells a listener that a widget was tapped', () async {
      const bridge = MethodChannelHomeWidgetBridge();
      var requests = 0;
      void listener() => requests++;
      bridge.listenForTab(listener);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            homeWidgetChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('tabRequested'),
            ),
            (_) {},
          );
      expect(requests, 1);

      bridge.stopListeningForTab(listener);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            homeWidgetChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('tabRequested'),
            ),
            (_) {},
          );
      expect(requests, 1);
    });
  });
}
