import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/shell/floating_tab_bar.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

const _screen = Size(390, 844);
const _capsule = ValueKey('tab-capsule');
const _pill = ValueKey('tab-selection-pill');

void _setScreen(WidgetTester tester, {double bottomInset = 0}) {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
  addTearDown(tester.view.reset);
}

/// The shell's arrangement: a body that extends under [FloatingBarFrame].
Widget _shell(
  Widget bar, {
  Widget body = const SizedBox.expand(),
  ThemeData? theme,
  TracendMotionLevel motion = TracendMotionLevel.static,
}) => MaterialApp(
  theme: theme ?? TracendTheme.dark,
  home: TracendMotionScope(
    level: motion,
    child: Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: FloatingBarFrame(child: bar),
    ),
  ),
);

/// Holds the selected tab the way the shell does.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => FloatingTabBar(
    selectedIndex: _index,
    onSelected: (index) => setState(() => _index = index),
  );
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void main() {
  group('position', () {
    testWidgets('floats above the home indicator on Face ID iPhones', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(_shell(const _Tabs()));

      final capsule = _rect(tester, _capsule);
      // 34pt inset less 10: a clear gap above the home indicator.
      expect(capsule.bottom, _screen.height - 24);
      expect(capsule.left, 20);
      expect(capsule.right, _screen.width - 20);
      expect(capsule.height, FloatingTabBar.height);
    });

    testWidgets('sits 12pt in without a bottom inset', (tester) async {
      _setScreen(tester);
      await tester.pumpWidget(_shell(const _Tabs()));

      final capsule = _rect(tester, _capsule);
      expect(capsule.bottom, _screen.height - 12);
      expect(capsule.left, 12);
      expect(capsule.right, _screen.width - 12);
    });

    testWidgets('the check-in gate bar takes the same position', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(
        _shell(
          CheckInGateBar(
            key: const ValueKey('gate'),
            onCheckIn: () {},
            onSkip: () {},
          ),
        ),
      );

      final gate = _rect(tester, const ValueKey('gate'));
      expect(gate.bottom, _screen.height - 24);
      expect(gate.left, 20);
      expect(gate.right, _screen.width - 20);
    });

    testWidgets('the body learns the bar height and ends clear of it', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      late double reported;
      await tester.pumpWidget(
        _shell(
          const _Tabs(),
          body: Builder(
            builder: (context) {
              reported = MediaQuery.paddingOf(context).bottom;
              return TracendScrollView(
                title: 'Train',
                children: [
                  for (var i = 0; i < 12; i++)
                    SizedBox(key: ValueKey('card-$i'), height: 120),
                ],
              );
            },
          ),
        ),
      );

      final capsule = _rect(tester, _capsule);
      // The whole slot: capsule plus the margin under it.
      expect(reported, _screen.height - capsule.top);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      // Scrolled to the end, the last card stops the clearance above the bar.
      expect(
        _rect(tester, const ValueKey('card-11')).bottom,
        capsule.top - TracendScrollView.endClearance,
      );
    });
  });

  group('selection', () {
    testWidgets('the pill follows the selected tab', (tester) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(_shell(const _Tabs()));

      for (final name in ['today', 'nutrition', 'progress', 'train']) {
        await tester.tap(find.byKey(ValueKey('tab-$name')));
        await tester.pumpAndSettle();
        expect(
          _rect(tester, _pill).center.dx,
          moreOrLessEquals(_rect(tester, ValueKey('tab-$name')).center.dx),
        );
      }
    });

    testWidgets('slides at full motion and jumps under Reduce Motion', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(
        _shell(const _Tabs(), motion: TracendMotionLevel.full),
      );
      final start = _rect(tester, _pill).center.dx;
      final target = _rect(tester, const ValueKey('tab-progress')).center.dx;

      await tester.tap(find.byKey(const ValueKey('tab-progress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midway = _rect(tester, _pill).center.dx;
      expect(midway, greaterThan(start));
      expect(midway, lessThan(target));
      await tester.pumpAndSettle();

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tab-today')));
      await tester.pump();
      expect(
        _rect(tester, _pill).center.dx,
        moreOrLessEquals(_rect(tester, const ValueKey('tab-today')).center.dx),
      );
    });

    testWidgets('selected tab uses lime ink; others secondary text', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(_shell(const _Tabs(), theme: TracendTheme.light));
      Color labelColor(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;

      expect(labelColor('Today'), TracendColors.light.accentSignalInk);
      expect(labelColor('Coach'), TracendColors.light.textSecondary);
    });
  });

  group('accessibility', () {
    testWidgets('keeps the tab semantics, selected state and 44pt targets', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(_shell(const _Tabs()));
      await tester.tap(find.byKey(const ValueKey('tab-coach')));
      await tester.pumpAndSettle();

      for (final name in ['today', 'train', 'coach', 'nutrition', 'progress']) {
        final tab = find.byKey(ValueKey('tab-$name'));
        expect(tab, findsOneWidget);
        final size = tester.getSize(tab);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(
        tester.getSemantics(find.byKey(const ValueKey('tab-coach'))),
        isSemantics(label: 'Coach tab', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('tab-today'))),
        isSemantics(label: 'Today tab', isSelected: false),
      );
    });

    testWidgets('labels clamp at large text without overflowing', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_shell(const _Tabs()));

      expect(tester.takeException(), isNull);
      expect(_rect(tester, _capsule).height, FloatingTabBar.height);
    });

    testWidgets('one glass layer in both themes', (tester) async {
      _setScreen(tester, bottomInset: 34);
      for (final theme in [TracendTheme.dark, TracendTheme.light]) {
        await tester.pumpWidget(_shell(const _Tabs(), theme: theme));
        expect(find.byType(TracendGlass), findsOneWidget);
        expect(find.byType(BackdropFilter), findsOneWidget);
      }
    });
  });
}
