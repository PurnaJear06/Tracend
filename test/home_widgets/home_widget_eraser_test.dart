import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';

import 'fake_home_widget_bridge.dart';

void main() {
  late FakeHomeWidgetBridge bridge;
  late HomeWidgetEraser eraser;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    bridge = FakeHomeWidgetBridge()..stored = {'local_date': '2026-10-18'};
    eraser = HomeWidgetEraser(bridge, preferences: SharedPreferencesAsync());
  });

  test('a clear that works leaves nothing pending', () async {
    expect(await eraser.erase(), isTrue);

    expect(bridge.stored, isNull);
    expect(await eraser.isPending(), isFalse);
  });

  test('a first failure is tried again at once', () async {
    bridge.failClears = 1;

    expect(await eraser.erase(), isTrue);

    expect(bridge.calls, ['clear', 'clear']);
    expect(await eraser.isPending(), isFalse);
  });

  test('two failures are kept for the next launch or resume', () async {
    bridge.failClears = 2;

    expect(await eraser.erase(), isFalse);
    expect(bridge.stored, isNotNull);
    expect(await eraser.isPending(), isTrue);

    // A new launch reads the flag from the phone.
    final launched = HomeWidgetEraser(
      bridge,
      preferences: SharedPreferencesAsync(),
    );
    bridge.failClears = 1;
    await launched.retryPending();
    expect(bridge.stored, isNull);
    expect(await launched.isPending(), isFalse);
  });

  test('retrying keeps the flag until a clear works', () async {
    bridge.failClears = 4;
    await eraser.erase();

    await eraser.retryPending();
    expect(await eraser.isPending(), isTrue);

    await eraser.retryPending();
    expect(await eraser.isPending(), isFalse);
    expect(bridge.stored, isNull);
  });

  test('with nothing pending a retry does not touch the widgets', () async {
    await eraser.retryPending();

    expect(bridge.calls, isEmpty);
    expect(bridge.stored, isNotNull);
  });
}
