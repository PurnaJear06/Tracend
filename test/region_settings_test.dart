import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/region_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

class _FakeRegion implements RegionRepository {
  _FakeRegion({
    this.stored,
    this.timeZoneGuess,
    this.failLoads = 0,
    this.failSaves = false,
  });

  String? stored;

  /// The country the account's time zone selects while none is stored.
  final String? timeZoneGuess;
  int failLoads;
  bool failSaves;
  final saved = <String?>[];

  AccountRegion get _now => AccountRegion(
    countryCode: stored,
    effectiveRegions: [
      'global',
      if (stored != null) stored! else ?timeZoneGuess,
    ],
  );

  @override
  Future<AccountRegion> load() async {
    if (failLoads > 0) {
      failLoads -= 1;
      throw Exception('offline');
    }
    return _now;
  }

  @override
  Future<AccountRegion> save(String? countryCode) async {
    if (failSaves) throw Exception('offline');
    saved.add(countryCode);
    stored = countryCode;
    return _now;
  }
}

Future<void> _pump(
  WidgetTester tester,
  RegionRepository region, {
  Size size = const Size(390, 1200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: AccountScreen(environment: _environment, region: region),
    ),
  );
  await tester.pumpAndSettle();
}

/// Region sits below the AI coach section, so the page is scrolled to it.
Future<void> _showRegion(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Country'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await _showRegion(tester);
  await tester.tap(find.text('Country'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no country the row says guidance applies everywhere', (
    tester,
  ) async {
    await _pump(tester, _FakeRegion());
    await _showRegion(tester);
    expect(find.text('Country'), findsOneWidget);
    expect(
      find.text('Not set · Coach uses guidance that applies everywhere'),
      findsOneWidget,
    );
  });

  testWidgets('with none set, a time-zone country is named, not hidden', (
    tester,
  ) async {
    await _pump(tester, _FakeRegion(timeZoneGuess: 'IN'));
    await _showRegion(tester);
    expect(
      find.text('Not set · Coach goes by your time zone or language (India)'),
      findsOneWidget,
    );
    expect(
      find.text('Not set · Coach uses guidance that applies everywhere'),
      findsNothing,
    );
  });

  testWidgets('a time-zone country with no national guidance stays global', (
    tester,
  ) async {
    await _pump(tester, _FakeRegion(timeZoneGuess: 'FR'));
    await _showRegion(tester);
    expect(
      find.text('Not set · Coach uses guidance that applies everywhere'),
      findsOneWidget,
    );
  });

  testWidgets('clearing the choice returns to the time-zone country', (
    tester,
  ) async {
    final region = _FakeRegion(stored: 'US', timeZoneGuess: 'IN');
    await _pump(tester, region);
    await _choose(tester, 'Not set');
    expect(region.saved, [null]);
    expect(
      find.text('Not set · Coach goes by your time zone or language (India)'),
      findsOneWidget,
    );
  });

  testWidgets('another country overrides the time zone', (tester) async {
    final region = _FakeRegion(timeZoneGuess: 'IN');
    await _pump(tester, region);
    await _choose(tester, 'Another country');
    expect(
      find.text(
        'Another country · Coach uses guidance that applies everywhere',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a stored country with national guidance is named', (
    tester,
  ) async {
    await _pump(tester, _FakeRegion(stored: 'IN'));
    await _showRegion(tester);
    expect(
      find.text('India · Coach can cite India’s national guidelines'),
      findsOneWidget,
    );
  });

  testWidgets('choosing a country stores it and the row follows', (
    tester,
  ) async {
    final region = _FakeRegion();
    await _pump(tester, region);
    await _choose(tester, 'Australia');
    expect(region.saved, ['AU']);
    expect(
      find.text('Australia · Coach can cite Australia’s national guidelines'),
      findsOneWidget,
    );
  });

  testWidgets('another country is stored apart from not set', (tester) async {
    final region = _FakeRegion(stored: 'GB');
    await _pump(tester, region);
    await _choose(tester, 'Another country');
    expect(region.saved, ['ZZ']);
    expect(
      find.text(
        'Another country · Coach uses guidance that applies everywhere',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Not set clears the country', (tester) async {
    final region = _FakeRegion(stored: 'US');
    await _pump(tester, region);
    await _choose(tester, 'Not set');
    expect(region.saved, [null]);
    expect(
      find.text('Not set · Coach uses guidance that applies everywhere'),
      findsOneWidget,
    );
  });

  testWidgets('picking the stored country again saves nothing', (tester) async {
    final region = _FakeRegion(stored: 'US');
    await _pump(tester, region);
    await _choose(tester, 'United States');
    expect(region.saved, isEmpty);
  });

  testWidgets('a failed save keeps the old country and says so', (
    tester,
  ) async {
    final region = _FakeRegion(stored: 'IN', failSaves: true);
    await _pump(tester, region);
    await _choose(tester, 'Australia');
    expect(
      find.text(
        'Your country was not saved. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('India · Coach can cite India’s national guidelines'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('an unreadable country can be tried again', (tester) async {
    final region = _FakeRegion(stored: 'GB', failLoads: 1);
    await _pump(tester, region);
    await _showRegion(tester);
    expect(find.text('Could not be read · open to try again'), findsOneWidget);
    await tester.tap(find.text('Country'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'United Kingdom · Coach can cite United Kingdom’s national guidelines',
      ),
      findsOneWidget,
    );
  });

  testWidgets('without a backend the row reads as not set', (tester) async {
    await _pump(tester, const FixtureRegionRepository());
    await _showRegion(tester);
    expect(
      find.text('Not set · Coach uses guidance that applies everywhere'),
      findsOneWidget,
    );
  });

  testWidgets('the row and its sheet lay out at 320pt × 2 text', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRegion(stored: 'GB'),
      size: const Size(320, 844),
      textScale: 2,
    );
    await _showRegion(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Country'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Another country'), findsOneWidget);
  });
}
