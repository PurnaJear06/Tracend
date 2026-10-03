import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/muscle_map_geometry.dart';

const _muscles = {
  MuscleGroup.chest: MuscleTone.main,
  MuscleGroup.back: MuscleTone.main,
  MuscleGroup.shoulders: MuscleTone.also,
};

/// Hosts a controlled [MuscleMap] like the screen does: the side lives
/// outside and drags report back through `onSideChanged`.
class _Host extends StatefulWidget {
  const _Host({required this.log, this.reduceMotion = false});
  final List<BodySide> log;
  final bool reduceMotion;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  BodySide side = BodySide.front;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(disableAnimations: widget.reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MuscleMap(
              muscles: _muscles,
              side: side,
              palette: MuscleMapPalette.dark,
              width: 140,
              onSideChanged: (next) {
                widget.log.add(next);
                setState(() => side = next);
              },
            ),
            GestureDetector(
              key: const ValueKey('toggle'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(
                () => side = side == BodySide.front
                    ? BodySide.back
                    : BodySide.front,
              ),
              child: const SizedBox(width: 40, height: 40),
            ),
          ],
        ),
      ),
    ),
  );
}

Matrix4? _faceTransform(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(MuscleMap),
      matching: find.byType(Transform),
    ),
  );
  return transforms.isEmpty ? null : transforms.last.transform;
}

MuscleFacePainter _facePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(MuscleMap),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<MuscleFacePainter>()
    .last;

void main() {
  testWidgets('one semantics label names the muscles and the side', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final log = <BodySide>[];
    await tester.pumpWidget(_Host(log: log));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Muscles worked: Chest, Back, Shoulders. Showing the front.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('toggle')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Muscles worked: Chest, Back, Shoulders. Showing the back.',
      ),
      findsOneWidget,
    );
    expect(
      muscleMapSemanticsLabel(const [], showing: 'front'),
      'No muscles linked to this workout. Showing the front.',
    );
    handle.dispose();
  });

  testWidgets('tones reach the painter; also is lime at 45% over off', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(log: []));
    await tester.pumpAndSettle();
    final painter = _facePainter(tester);
    expect(painter.tones, _muscles);
    expect(painter.reveal.values, everyElement(1.0));
    expect(painter.figure, BodyFigure.front);
    const palette = MuscleMapPalette.dark;
    expect(
      palette.also,
      Color.alphaBlend(
        const Color(0xFFC8F05A).withValues(alpha: 0.45),
        const Color(0xFF34363A),
      ),
    );
    expect(MuscleMapPalette.light.off, const Color(0xFFD6D6D0));
    expect(MuscleMapPalette.light.base, const Color(0xFFE6E6E1));
  });

  testWidgets('the intro lights the muscles in turn and settles', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(log: []));
    await tester.pump(const Duration(milliseconds: 250));
    final early = _facePainter(tester).reveal;
    expect(early[MuscleGroup.chest]!, greaterThan(early[MuscleGroup.back]!));
    expect(early[MuscleGroup.shoulders], 0);
    await tester.pumpAndSettle();
    expect(_facePainter(tester).reveal.values, everyElement(1.0));
  });

  testWidgets('a drag past halfway snaps to the back and reports it', (
    tester,
  ) async {
    final log = <BodySide>[];
    await tester.pumpWidget(_Host(log: log));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MuscleMap), const Offset(110, 0));
    await tester.pumpAndSettle();
    expect(log, [BodySide.back]);
    expect(_facePainter(tester).figure, BodyFigure.back);
  });

  testWidgets('a short slow drag springs back to the front', (tester) async {
    final log = <BodySide>[];
    await tester.pumpWidget(_Host(log: log));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MuscleMap)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(log, isEmpty);
    expect(_facePainter(tester).figure, BodyFigure.front);
    expect(_faceTransform(tester)!.getRotation().entry(0, 0), closeTo(1, 1e-6));
  });

  testWidgets('a quick flick turns the figure on velocity', (tester) async {
    final log = <BodySide>[];
    await tester.pumpWidget(_Host(log: log));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(MuscleMap), const Offset(70, 0), 1500);
    await tester.pumpAndSettle();
    expect(log, [BodySide.back]);
  });

  testWidgets('the side control turns the figure from outside', (tester) async {
    await tester.pumpWidget(_Host(log: []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-turn: the edge-on body draws its thickness slices.
    expect(
      tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(MuscleMap),
              matching: find.byType(CustomPaint),
            ),
          )
          .length,
      greaterThan(3),
    );
    await tester.pumpAndSettle();
    expect(_facePainter(tester).figure, BodyFigure.back);
  });

  testWidgets('Reduce Motion crossfades with no sway, stagger or turn', (
    tester,
  ) async {
    final log = <BodySide>[];
    await tester.pumpWidget(_Host(log: log, reduceMotion: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_faceTransform(tester), isNull);
    final opacities = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, [1, 0]);
    for (final painter
        in tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<MuscleFacePainter>()) {
      expect(painter.reveal.values, everyElement(1.0));
    }

    await tester.fling(find.byType(MuscleMap), const Offset(60, 0), 800);
    await tester.pumpAndSettle();
    expect(log, [BodySide.back]);
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((o) => o.opacity),
      [0, 1],
    );
    expect(_faceTransform(tester), isNull);
  });

  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: MuscleMap(
            muscles: _muscles,
            side: BodySide.front,
            palette: MuscleMapPalette.dark,
            introAnimation: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MuscleMap));
    expect(taps, 1);
  });

  testWidgets('the pair hit-tests a tapped muscle to its group', (
    tester,
  ) async {
    final tapped = <MuscleGroup>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: MuscleMapPair(
            muscles: _muscles,
            palette: MuscleMapPalette.dark,
            figureWidth: 200,
            onMuscleTap: tapped.add,
          ),
        ),
      ),
    );
    final faces = find.descendant(
      of: find.byType(MuscleMapPair),
      matching: find.byType(GestureDetector),
    );
    final front = tester.getTopLeft(faces.at(0));
    final back = tester.getTopLeft(faces.at(1));
    await tester.tapAt(front + const Offset(82, 95)); // left pec
    await tester.tapAt(front + const Offset(200 - 82, 95)); // mirrored pec
    await tester.tapAt(front + const Offset(78, 250)); // rectus femoris
    await tester.tapAt(front + const Offset(100, 28)); // head: neutral
    await tester.tapAt(back + const Offset(84, 224)); // glute
    await tester.tapAt(back + const Offset(42, 130)); // triceps
    expect(tapped, [
      MuscleGroup.chest,
      MuscleGroup.chest,
      MuscleGroup.quads,
      MuscleGroup.glutes,
      MuscleGroup.triceps,
    ]);
  });

  testWidgets('the selected group pulses; Reduce Motion holds it still', (
    tester,
  ) async {
    Widget pair({required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: MuscleMapPair(
          muscles: _muscles,
          palette: MuscleMapPalette.dark,
          selected: MuscleGroup.chest,
        ),
      ),
    );
    await tester.pumpWidget(pair(reduce: false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);
    final pulse = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<MuscleFacePainter>()
        .first
        .pulse;
    expect(pulse, greaterThan(0));

    await tester.pumpWidget(pair(reduce: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('no ticker or timer outlives dispose', (tester) async {
    await tester.pumpWidget(_Host(log: []));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MuscleMapPair(
          muscles: _muscles,
          palette: MuscleMapPalette.dark,
          selected: MuscleGroup.back,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
