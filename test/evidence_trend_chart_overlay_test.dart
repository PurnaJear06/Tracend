import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/evidence_trend_chart.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

List<DatedTrendValue> _series() => [
  DatedTrendValue(DateTime(2026, 8, 1), 80.0),
  DatedTrendValue(DateTime(2026, 8, 8), 79.6),
  DatedTrendValue(DateTime(2026, 8, 15), 79.2),
  DatedTrendValue(DateTime(2026, 8, 22), 78.8),
];

void main() {
  group('deriveTrendOverlay', () {
    test(
      'anchors the line to the window centroid, not an invented intercept',
      () {
        final overlay = deriveTrendOverlay(
          _series(),
          windowDays: 7,
          slopeKgPerDay: -0.05,
        )!;
        // 7-day window ending 2026-08-22 = 2026-08-16…2026-08-22.
        // Only the 2026-08-22 point (78.8) is inside it, so the centroid is
        // that measurement and the line passes through it at the window end.
        expect(overlay.end.value, closeTo(78.8, 1e-9));
        expect(overlay.end.date, DateTime(2026, 8, 22));
      },
    );

    test('limits the line to its applicable window', () {
      final overlay = deriveTrendOverlay(
        _series(),
        windowDays: 7,
        slopeKgPerDay: -0.05,
      )!;
      expect(overlay.start.date, DateTime(2026, 8, 16));
      expect(overlay.end.date, DateTime(2026, 8, 22));
    });

    test('28-day window spans the full series', () {
      final overlay = deriveTrendOverlay(
        _series(),
        windowDays: 28,
        slopeKgPerDay: -0.04,
      )!;
      expect(overlay.start.date, DateTime(2026, 8, 1));
      expect(overlay.end.date, DateTime(2026, 8, 22));
    });

    test('returns null when the window has no measurement evidence', () {
      final overlay = deriveTrendOverlay(
        [DatedTrendValue(DateTime(2026, 1, 1), 80.0)],
        windowDays: 7,
        slopeKgPerDay: -0.05,
      );
      // Single point at chart start: window ending that date has the point,
      // but endDays == 0 so no drawable segment exists.
      expect(overlay, isNull);
    });

    test('returns null for empty values', () {
      expect(
        deriveTrendOverlay([], windowDays: 7, slopeKgPerDay: -0.05),
        isNull,
      );
    });

    test('lowConfidence is caller-decided (R2 semantics live outside)', () {
      final confident = deriveTrendOverlay(
        _series(),
        windowDays: 28,
        slopeKgPerDay: -0.04,
        lowConfidence: false,
      )!;
      final low = deriveTrendOverlay(
        _series(),
        windowDays: 28,
        slopeKgPerDay: -0.04,
        lowConfidence: true,
      )!;
      expect(confident.lowConfidence, isFalse);
      expect(low.lowConfidence, isTrue);
    });
  });

  group('EvidenceTrendChart overlays', () {
    testWidgets('measured-only shows no trend legend', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
          ),
        ),
      );
      expect(find.text('Measured'), findsNothing);
      expect(find.textContaining('7-day trend'), findsNothing);
      expect(find.textContaining('28-day trend'), findsNothing);
    });

    testWidgets('7-day overlay renders its legend entry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope7d: -0.05,
          ),
        ),
      );
      expect(find.text('Measured'), findsOneWidget);
      expect(find.text('7-day trend'), findsOneWidget);
      expect(find.textContaining('28-day trend'), findsNothing);
    });

    testWidgets('28-day overlay renders its legend entry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope28d: -0.04,
            trendR2: 0.8,
          ),
        ),
      );
      expect(find.text('28-day trend'), findsOneWidget);
      expect(find.textContaining('7-day trend'), findsNothing);
    });

    testWidgets('both overlays render both legend entries', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope7d: -0.05,
            trendSlope28d: -0.04,
            trendR2: 0.8,
          ),
        ),
      );
      expect(find.text('7-day trend'), findsOneWidget);
      expect(find.text('28-day trend'), findsOneWidget);
    });

    testWidgets('low R2 marks the 28-day line low confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope28d: -0.04,
            trendR2: 0.1,
          ),
        ),
      );
      expect(find.text('28-day trend · low confidence'), findsOneWidget);
    });

    testWidgets('missing R2 marks the 28-day line low confidence', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope28d: -0.04,
          ),
        ),
      );
      expect(find.text('28-day trend · low confidence'), findsOneWidget);
    });

    testWidgets('7-day line is never confidence-gated by R2', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope7d: -0.05,
            trendR2: 0.1,
          ),
        ),
      );
      // R2 describes only the 28-day window; the 7-day line stays plain.
      expect(find.text('7-day trend'), findsOneWidget);
      expect(find.textContaining('7-day trend · low confidence'), findsNothing);
    });

    testWidgets('null trend fields render measured-only', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: _series(),
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope7d: null,
            trendSlope28d: null,
            trendR2: null,
          ),
        ),
      );
      expect(find.text('Measured'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('single measurement renders without overlays', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: [DatedTrendValue(DateTime(2026, 8, 22), 78.8)],
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope7d: -0.05,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('7-day trend'), findsNothing);
    });

    testWidgets('unsorted measurements are ordered before overlay derivation', (
      tester,
    ) async {
      final unsorted = [
        DatedTrendValue(DateTime(2026, 8, 22), 78.8),
        DatedTrendValue(DateTime(2026, 8, 1), 80.0),
        DatedTrendValue(DateTime(2026, 8, 15), 79.2),
        DatedTrendValue(DateTime(2026, 8, 8), 79.6),
      ];
      await tester.pumpWidget(
        _wrap(
          EvidenceTrendChart(
            values: unsorted,
            unit: 'kg',
            semanticLabel: 'weight',
            trendSlope28d: -0.04,
            trendR2: 0.8,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('28-day trend'), findsOneWidget);
    });

    testWidgets(
      'semantics distinguish measured evidence from computed trends',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            EvidenceTrendChart(
              values: _series(),
              unit: 'kg',
              semanticLabel: 'Weight trend.',
              trendSlope7d: -0.05,
              trendSlope28d: -0.04,
              trendR2: 0.8,
            ),
          ),
        );
        final label = tester
            .widget<Semantics>(find.bySemanticsLabel(RegExp('Weight trend')))
            .properties
            .label!;
        expect(label, contains('measured evidence'));
        expect(label, contains('computed models'));
        expect(label, contains('7-day trend'));
        expect(label, contains('28-day trend'));
      },
    );
  });
}
