import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Headline snapshot: latest confirmed weigh-in and timeline change.
/// Every number traces to a confirmed [BodyMeasurement] or the
/// deterministic `get_my_progress_summary` RPC — never an AI estimate.
class ProgressSnapshotCard extends StatelessWidget {
  const ProgressSnapshotCard({
    required this.measurements,
    required this.fallback,
    super.key,
  });

  final List<BodyMeasurement> measurements;
  final ProgressSummary fallback;

  @override
  Widget build(BuildContext context) {
    final current = measurements.isEmpty
        ? fallback.currentWeightKg
        : measurements.last.weightKg;
    final change = measurements.length >= 2
        ? measurements.last.weightKg - measurements.first.weightKg
        : fallback.weightChangeKg;
    return PremiumGradientCard(
      glow: true,
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TracendPill(
            label: measurements.length >= 2
                ? '${measurements.length} confirmed days'
                : 'Gathering baseline',
            icon: measurements.length >= 2
                ? CupertinoIcons.chart_bar_fill
                : CupertinoIcons.plus_circle_fill,
            color: measurements.length >= 2
                ? context.tracendColors.stateStable
                : context.tracendColors.actionPrimary,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            current == null
                ? 'Add your first weigh-in'
                : '${current.toStringAsFixed(1)} kg',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            change == null
                ? 'Use the same morning protocol when practical.'
                : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg across your confirmed timeline.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            'Latest confirmed weigh-in · no AI estimate',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class EmptyMeasurementsCard extends StatelessWidget {
  const EmptyMeasurementsCard({super.key});

  @override
  Widget build(BuildContext context) => const TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.chart_bar),
        SizedBox(height: 12),
        Text('No measurements yet'),
        SizedBox(height: 4),
        Text(
          'Your first confirmed entry becomes the baseline. A trend needs at least two dates.',
        ),
      ],
    ),
  );
}

/// One confirmed measurement row. Tappable: opens [MeasurementDetailSheet]
/// so the "Tap a history row to verify" copy is a real affordance.
class MeasurementHistoryRow extends StatelessWidget {
  const MeasurementHistoryRow({
    required this.value,
    required this.onOpen,
    super.key,
  });

  final BodyMeasurement value;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      button: true,
      label:
          'Weigh-in ${value.weightKg.toStringAsFixed(1)} kilograms on '
          '${value.date.day}/${value.date.month}/${value.date.year}, '
          'source ${value.source}. Opens details.',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(TracendRadii.card),
        child: TracendCard(
          child: Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal_fill,
                color: colors.stateStable,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${value.weightKg.toStringAsFixed(1)} kg',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${value.date.day}/${value.date.month}/${value.date.year} · ${value.source}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (value.waistCm != null)
                Text(
                  '${value.waistCm!.toStringAsFixed(1)} cm waist',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              const SizedBox(width: TracendSpacing.xs),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail sheet for one confirmed measurement: date, source, weight, and
/// optional tape measurements. Read-only — editing is not a confirmed flow.
class MeasurementDetailSheet extends StatelessWidget {
  const MeasurementDetailSheet({required this.measurement, super.key});

  final BodyMeasurement measurement;

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirmed weigh-in',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${measurement.date.day}/${measurement.date.month}/${measurement.date.year} · source: ${measurement.source}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Confirmed entries are evidence. They are never edited silently.',
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
              'Confirmed manual entry · kilograms and centimeters',
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
