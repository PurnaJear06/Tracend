import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';

import 'haptics_recorder.dart';
import 'widget_host.dart';

void main() {
  Future<Future<T>> launch<T>(
    WidgetTester tester,
    Future<T> Function(BuildContext context) show,
  ) async {
    late Future<T> result;
    await tester.pumpWidget(
      widgetHost(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => result = show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<bool> Function(BuildContext) confirm({bool destructive = false}) =>
      (context) => showTracendConfirm(
        context,
        title: 'Discard this workout?',
        message: 'The sets you logged today are deleted.',
        confirmLabel: 'Discard workout',
        destructive: destructive,
      );

  testWidgets('confirm completes true when confirmed', (tester) async {
    final result = await launch(tester, confirm());

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('The sets you logged today are deleted.'), findsOneWidget);
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  testWidgets('confirm completes false on cancel', (tester) async {
    final result = await launch(tester, confirm());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('destructive confirm uses the danger color, makes cancel the '
      'default and plays the warning haptic', (tester) async {
    final haptics = recordHaptics(tester);
    await launch(tester, confirm(destructive: true));

    final actions = tester
        .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
        .toList();
    expect(actions.first.isDefaultAction, isTrue);
    expect(actions.last.isDestructiveAction, isTrue);
    final label = tester.widget<Text>(find.text('Discard workout'));
    expect(label.style?.color, TracendColors.dark.stateDanger);
    expect(haptics, ['HapticFeedbackType.warningNotification']);
  });

  testWidgets('a non-destructive confirm plays no haptic', (tester) async {
    final haptics = recordHaptics(tester);
    await launch(tester, confirm());

    final label = tester.widget<Text>(find.text('Discard workout'));
    expect(label.style?.color, TracendColors.dark.textPrimary);
    expect(haptics, isEmpty);
  });

  Future<String?> Function(BuildContext) actionSheet() =>
      (context) => showTracendActionSheet<String>(
        context,
        title: 'Leave this workout?',
        message: '3 sets are saved on your phone.',
        actions: const [
          TracendSheetAction(
            label: 'Save and leave',
            value: 'save',
            isDefault: true,
          ),
          TracendSheetAction(
            label: 'Discard workout',
            value: 'discard',
            destructive: true,
          ),
        ],
      );

  testWidgets('action sheet completes with the chosen value', (tester) async {
    final result = await launch(tester, actionSheet());

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();

    expect(await result, 'discard');
  });

  testWidgets('action sheet cancel completes with null and styles the '
      'destructive choice', (tester) async {
    final result = await launch(tester, actionSheet());

    final discard = tester.widget<Text>(find.text('Discard workout'));
    expect(discard.style?.color, TracendColors.dark.stateDanger);
    final save = tester.widget<Text>(find.text('Save and leave'));
    expect(save.style?.fontWeight, FontWeight.w600);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
