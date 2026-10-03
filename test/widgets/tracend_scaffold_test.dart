import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

import 'widget_host.dart';

void main() {
  group('StatusChip', () {
    Color iconColor(WidgetTester tester, String label) => tester
        .widget<Icon>(
          find.descendant(
            of: find.widgetWithText(StatusChip, label),
            matching: find.byType(Icon),
          ),
        )
        .color!;

    testWidgets('each tone uses its own semantic color', (tester) async {
      await tester.pumpWidget(
        widgetHost(
          const Column(
            children: [
              StatusChip(
                label: 'Saved and synced',
                icon: CupertinoIcons.check_mark,
                tone: StatusTone.good,
              ),
              StatusChip(
                label: 'Sync pending',
                icon: CupertinoIcons.wifi_slash,
                tone: StatusTone.caution,
              ),
              StatusChip(
                label: 'Sync failed',
                icon: CupertinoIcons.xmark,
                tone: StatusTone.low,
              ),
              StatusChip(label: 'Autosave is ready', icon: CupertinoIcons.info),
              StatusChip(
                label: 'New best',
                icon: CupertinoIcons.star,
                tone: StatusTone.signal,
              ),
            ],
          ),
        ),
      );
      const colors = TracendColors.dark;

      expect(iconColor(tester, 'Saved and synced'), colors.stateStable);
      expect(iconColor(tester, 'Sync pending'), colors.accentAmber);
      expect(iconColor(tester, 'Sync failed'), colors.stateAttention);
      expect(iconColor(tester, 'Autosave is ready'), colors.textSecondary);
      expect(iconColor(tester, 'New best'), colors.accentSignalInk);
    });

    testWidgets('a warning never renders green and labels stay primary', (
      tester,
    ) async {
      await tester.pumpWidget(
        widgetHost(
          const StatusChip(
            label: 'Workout record needs review',
            icon: CupertinoIcons.exclamationmark_triangle,
            tone: StatusTone.caution,
          ),
        ),
      );

      expect(
        iconColor(tester, 'Workout record needs review'),
        isNot(TracendColors.dark.stateStable),
      );
      final label = tester.widget<Text>(
        find.text('Workout record needs review'),
      );
      expect(label.style?.color, TracendColors.dark.textPrimary);
    });
  });

  group('SectionLabel', () {
    testWidgets('renders sentence case as a 20pt Archivo header', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        widgetHost(const SectionLabel('Exercises', value: '16 sets')),
      );

      expect(find.text('Exercises'), findsOneWidget);
      expect(find.text('EXERCISES'), findsNothing);
      expect(find.text('16 sets'), findsOneWidget);
      final style = tester.widget<Text>(find.text('Exercises')).style!;
      expect(style.fontSize, 20);
      expect(style.fontFamily, TracendFonts.displayFamily);
      expect(
        tester.getSemantics(find.text('Exercises')),
        matchesSemantics(label: 'Exercises', isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('offers a trailing action', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        widgetHost(
          SectionLabel(
            'Recent workouts',
            actionLabel: 'See all',
            onAction: () => opened++,
          ),
        ),
      );

      await tester.tap(find.text('See all'));
      expect(opened, 1);
    });
  });

  group('TracendScrollView', () {
    Widget page({Future<void> Function()? onRefresh, ThemeData? theme}) =>
        widgetHost(
          theme: theme,
          TracendScrollView(
            title: 'Train',
            subtitle: 'Thursday 2 October',
            onRefresh: onRefresh,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 60, child: Text('Row $i')),
            ],
          ),
        );

    testWidgets('large title is Archivo displaySmall', (tester) async {
      await tester.pumpWidget(page());

      final style = tester.widget<Text>(find.text('Train')).style!;
      expect(
        style.fontSize,
        TracendTheme.dark.textTheme.displaySmall!.fontSize,
      );
      expect(style.fontFamily, TracendFonts.displayFamily);
      expect(find.text('Thursday 2 October'), findsOneWidget);
      expect(find.byType(TracendGlass), findsNothing);
    });

    testWidgets('collapses into a glass inline bar on scroll and back', (
      tester,
    ) async {
      await tester.pumpWidget(page());

      await tester.drag(find.text('Row 3'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TracendGlass),
          matching: find.text('Train'),
        ),
        findsOneWidget,
      );

      await tester.drag(find.text('Row 6'), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(TracendGlass), findsNothing);
      expect(find.text('Train'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Train')).dy, greaterThan(0));
    });

    testWidgets('a short scroll keeps the large title', (tester) async {
      await tester.pumpWidget(page());

      await tester.drag(find.text('Row 3'), const Offset(0, -24));
      await tester.pumpAndSettle();
      expect(find.byType(TracendGlass), findsNothing);
    });

    testWidgets('pull to refresh calls onRefresh', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(
        page(
          onRefresh: () async {
            refreshes++;
          },
        ),
      );

      expect(
        find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        findsOneWidget,
      );
      await tester.fling(find.text('Train'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });

    testWidgets('no refresh control without onRefresh', (tester) async {
      await tester.pumpWidget(page());
      expect(
        find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        findsNothing,
      );
    });
  });
}
