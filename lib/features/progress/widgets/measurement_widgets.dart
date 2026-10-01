import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// The latest weigh-ins as one grouped list. Each row shows the change from
/// the weigh-in before it, a plain difference of two confirmed values.
class WeighInList extends StatelessWidget {
  const WeighInList({
    required this.measurements,
    required this.onOpen,
    this.limit,
    this.now,
    super.key,
  });

  /// Every confirmed weigh-in, oldest first.
  final List<BodyMeasurement> measurements;
  final ValueChanged<BodyMeasurement> onOpen;

  /// Show only the newest [limit] rows when set.
  final int? limit;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final newestFirst = measurements.reversed.toList();
    final shown = limit == null
        ? newestFirst
        : newestFirst.take(limit!).toList();
    return TracendGroupedList(
      children: [
        for (var i = 0; i < shown.length; i++)
          _WeighInRow(
            value: shown[i],
            previous: i + 1 < newestFirst.length ? newestFirst[i + 1] : null,
            onOpen: () => onOpen(shown[i]),
            now: now,
            colors: colors,
          ),
      ],
    );
  }
}

class _WeighInRow extends StatelessWidget {
  const _WeighInRow({
    required this.value,
    required this.previous,
    required this.onOpen,
    required this.now,
    required this.colors,
  });

  final BodyMeasurement value;
  final BodyMeasurement? previous;
  final VoidCallback onOpen;
  final DateTime? now;
  final TracendColors colors;

  @override
  Widget build(BuildContext context) {
    final date = friendlyDate(value.date, now: now);
    final source = measurementSourceLabel(value.source);
    final delta = previous == null
        ? null
        : double.parse(
            (value.weightKg - previous!.weightKg).toStringAsFixed(1),
          );
    return TracendListRow(
      title: '${value.weightKg.toStringAsFixed(1)} kg',
      subtitle: '$date · $source',
      semanticLabel:
          'Weigh-in ${value.weightKg.toStringAsFixed(1)} kilograms, $date, '
          '$source. Opens details.',
      onTap: onOpen,
      trailing: delta == null
          ? null
          : Text(
              delta == 0
                  ? '0.0'
                  : '${delta > 0 ? '+' : '\u2212'}${delta.abs().toStringAsFixed(1)}',
              style: TracendTheme.dataUtility(colors),
            ),
    );
  }
}

/// Every weigh-in, newest first, in a scrollable sheet.
class WeighInHistorySheet extends StatelessWidget {
  const WeighInHistorySheet({
    required this.measurements,
    required this.onOpen,
    this.now,
    super.key,
  });

  final List<BodyMeasurement> measurements;
  final ValueChanged<BodyMeasurement> onOpen;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        0,
        TracendSpacing.gutter,
        TracendSpacing.xl,
      ),
      children: [
        Text('All weigh-ins', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          '${measurements.length} recorded',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.md),
        WeighInList(measurements: measurements, onOpen: onOpen, now: now),
      ],
    ),
  );
}

/// Detail sheet for one confirmed measurement: date, source, weight, and
/// optional tape measurements. Read-only — editing is not a confirmed flow.
class MeasurementDetailSheet extends StatelessWidget {
  const MeasurementDetailSheet({
    required this.measurement,
    this.now,
    super.key,
  });

  final BodyMeasurement measurement;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final rows = <(String, String)>[
      ('Weight', '${measurement.weightKg.toStringAsFixed(1)} kg'),
      if (measurement.waistCm != null)
        ('Waist', '${measurement.waistCm!.toStringAsFixed(1)} cm'),
      if (measurement.chestCm != null)
        ('Chest', '${measurement.chestCm!.toStringAsFixed(1)} cm'),
      if (measurement.hipCm != null)
        ('Hip', '${measurement.hipCm!.toStringAsFixed(1)} cm'),
      if (measurement.armCm != null)
        ('Arm', '${measurement.armCm!.toStringAsFixed(1)} cm'),
      if (measurement.thighCm != null)
        ('Thigh', '${measurement.thighCm!.toStringAsFixed(1)} cm'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.gutter,
          0,
          TracendSpacing.gutter,
          TracendSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              friendlyDate(measurement.date, now: now),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              measurementSourceLabel(measurement.source),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.md),
            TracendGroupedList(
              children: [
                for (final (label, value) in rows)
                  TracendListRow(
                    title: label,
                    trailing: Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Saved weigh-ins are never changed behind your back.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Manual measurement entry form (confirmed write via `save_body_measurement`).
class MeasurementEntrySheet extends StatefulWidget {
  const MeasurementEntrySheet({super.key});

  @override
  State<MeasurementEntrySheet> createState() => _MeasurementEntrySheetState();
}

class _MeasurementEntrySheetState extends State<MeasurementEntrySheet> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(6, (_) => TextEditingController());

  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  double? n(int i) => fields[i].text.trim().isEmpty
      ? null
      : double.tryParse(fields[i].text.trim());

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Form(
      key: form,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record measurement',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Only weight is required. Weigh in at the same time of day, '
              'ideally in the morning, for the clearest trend.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...[
              'Weight *',
              'Waist',
              'Chest',
              'Hip',
              'Arm',
              'Thigh',
            ].asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: fields[e.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: e.key == 5
                      ? TextInputAction.done
                      : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: e.value,
                    suffixText: e.key == 0 ? 'kg' : 'cm',
                  ),
                  validator: (v) {
                    if (e.key == 0 && n(0) == null) {
                      return 'Enter a valid weight';
                    }
                    if (v!.isNotEmpty && n(e.key) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    BodyMeasurement(
                      date: DateTime.now(),
                      weightKg: n(0)!,
                      waistCm: n(1),
                      chestCm: n(2),
                      hipCm: n(3),
                      armCm: n(4),
                      thighCm: n(5),
                    ),
                  );
                },
                child: const Text('Save measurement'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
