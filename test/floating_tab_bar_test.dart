import 'package:flutter/foundation.dart';
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

/// A portrait iPhone with a [bottomInset] home-indicator inset and, when
/// [keyboard] is above zero, the keyboard up. As on iOS, the keyboard eats
/// into the padding but not the view padding.
void _setScreen(
  WidgetTester tester, {
  double bottomInset = 0,
  double keyboard = 0,
  Size size = _screen,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(top: 47, bottom: bottomInset);
  tester.view.padding = FakeViewPadding(
    top: 47,
    bottom: (bottomInset - keyboard).clamp(0, bottomInset),
  );
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
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

/// Swaps between the gate bar and the tab capsule the way the shell does.
class _GateOrTabs extends StatelessWidget {
  const _GateOrTabs(this.gated);

  final ValueListenable<bool> gated;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: gated,
    builder: (context, gated, _) => FloatingBarSwitcher(
      child: gated
          ? CheckInGateBar(
              key: const ValueKey('gate'),
              onCheckIn: () {},
              onSkip: () {},
            )
          : FloatingTabBar(
              key: const ValueKey('tabs'),
              selectedIndex: 0,
              onSelected: (_) {},
            ),
    ),
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

    testWidgets('keeps its place and width while the keyboard is up', (
      tester,
    ) async {
      Rect? before;
      for (final keyboard in [0.0, 20.0, 34.0, 100.0]) {
        _setScreen(tester, bottomInset: 34, keyboard: keyboard);
        await tester.pumpWidget(_shell(const _Tabs()));
        final capsule = _rect(tester, _capsule);
        expect(
          capsule.bottom,
          _screen.height - 24,
          reason: 'keyboard $keyboard',
        );
        expect(capsule.left, 20, reason: 'keyboard $keyboard');
        expect(capsule, before ?? capsule, reason: 'keyboard $keyboard');
        before = capsule;
      }
    });

    testWidgets('clears the home indicator in landscape', (tester) async {
      // Landscape iPhones report a 21pt bottom inset.
      _setScreen(tester, bottomInset: 21, size: const Size(844, 390));
      await tester.pumpWidget(_shell(const _Tabs()));

      expect(_rect(tester, _capsule).bottom, 390 - 20);
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

  group('swap', () {
    testWidgets('neither bar leaves the bottom edge, and content glides', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      final gated = ValueNotifier(true);
      addTearDown(gated.dispose);
      final padding = <double>[];
      await tester.pumpWidget(
        _shell(
          _GateOrTabs(gated),
          motion: TracendMotionLevel.full,
          body: Builder(
            builder: (context) {
              padding.add(MediaQuery.paddingOf(context).bottom);
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      const bottom = 844.0 - 24;
      expect(_rect(tester, const ValueKey('gate')).bottom, bottom);

      for (final gate in [false, true, false]) {
        gated.value = gate;
        await tester.pump();
        for (var frame = 0; frame < 30; frame++) {
          for (final key in [_capsule, const ValueKey('gate')]) {
            if (find.byKey(key).evaluate().isEmpty) continue;
            expect(
              _rect(tester, key).bottom,
              moreOrLessEquals(bottom),
              reason: '$key, frame $frame',
            );
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      }

      // The body's bottom padding eases between the two slot heights (about
      // 98pt apart) frame by frame instead of snapping at the end.
      final gateSlot = padding.first;
      expect(gateSlot - padding.last, greaterThan(60));
      for (var i = 1; i < padding.length; i++) {
        expect(
          (padding[i] - padding[i - 1]).abs(),
          lessThan((gateSlot - padding.last) / 6),
          reason: 'step $i: ${padding[i - 1]} -> ${padding[i]}',
        );
      }
      expect(padding.last, FloatingTabBar.height + 24);
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

    testWidgets('selection reads by weight and ring, not only by color', (
      tester,
    ) async {
      _setScreen(tester, bottomInset: 34);
      await tester.pumpWidget(_shell(const _Tabs(), theme: TracendTheme.light));
      const colors = TracendColors.light;
      TextStyle label(String text) =>
          tester.widget<Text>(find.text(text)).style!;
      Color icon(String tab) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(ValueKey('tab-$tab')),
              matching: find.byType(Icon),
            ),
          )
          .color!;

      expect(icon('today'), colors.accentSignalInk);
      expect(label('Today').color, colors.textPrimary);
      expect(label('Today').fontWeight, FontWeight.w700);
      expect(icon('coach'), colors.textSecondary);
      expect(label('Coach').color, colors.textSecondary);
      expect(label('Coach').fontWeight, FontWeight.w600);
      final pill = tester.widget<DecoratedBox>(find.byKey(_pill));
      final border = (pill.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, colors.accentSignalRing);
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
