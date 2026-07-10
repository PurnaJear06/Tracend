import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/trajectory_lens.dart';

class ComponentGalleryApp extends StatelessWidget {
  const ComponentGalleryApp({this.themeMode = ThemeMode.system, super.key});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracend component gallery',
      debugShowCheckedModeBanner: false,
      theme: TracendTheme.light,
      darkTheme: TracendTheme.dark,
      themeMode: themeMode,
      home: const ComponentGalleryScreen(),
    );
  }
}

class ComponentGalleryScreen extends StatelessWidget {
  const ComponentGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TracendScrollView(
        title: 'Component gallery',
        subtitle: 'Phase 1 · semantic UI reference',
        children: [
          const _GalleryNote(),
          const SectionLabel('Color roles'),
          const _ColorRoles(),
          const SectionLabel('Typography'),
          const _TypographySpecimen(),
          const SectionLabel('Actions'),
          const _ActionSpecimen(),
          const SectionLabel('Evidence'),
          const TracendCard(
            child: TrajectoryLens(
              evidence: [
                'Sleep stable',
                'Training on plan',
                'Nutrition on target',
              ],
              decision: 'Maintain plan',
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
          const StatusChip(
            label: 'Confirmed data · current',
            icon: CupertinoIcons.checkmark_shield_fill,
          ),
          const SectionLabel('Metrics'),
          const TracendCard(
            child: Column(
              children: [
                MetricRow(label: 'Sleep', value: '7h 42m', detail: 'Stable'),
                Divider(height: TracendSpacing.xl),
                MetricRow(label: 'Training', value: 'On plan', detail: 'Push'),
              ],
            ),
          ),
          const SectionLabel('System states'),
          const _SystemStates(),
        ],
      ),
    );
  }
}

class _GalleryNote extends StatelessWidget {
  const _GalleryNote();

  @override
  Widget build(BuildContext context) {
    return TracendCard(
      radius: TracendRadii.decision,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.scope,
            color: context.tracendColors.actionPrimary,
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Text(
              'A development-only surface for checking tokens, components, '
              'Dynamic Type, contrast, and semantic reading order.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorRoles extends StatelessWidget {
  const _ColorRoles();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - TracendSpacing.sm) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: TracendSpacing.sm,
          runSpacing: TracendSpacing.sm,
          children: [
            _ColorRole(
              label: 'Primary action',
              color: colors.actionPrimary,
              width: width,
            ),
            _ColorRole(
              label: 'Stable state',
              color: colors.stateStable,
              width: width,
            ),
            _ColorRole(
              label: 'Attention state',
              color: colors.stateAttention,
              width: width,
            ),
            _ColorRole(
              label: 'Raised surface',
              color: colors.surfaceRaised,
              width: width,
              bordered: true,
            ),
          ],
        );
      },
    );
  }
}

class _ColorRole extends StatelessWidget {
  const _ColorRole({
    required this.label,
    required this.color,
    required this.width,
    this.bordered = false,
  });

  final String label;
  final Color color;
  final double width;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(TracendRadii.control),
              border: bordered
                  ? Border.all(color: context.tracendColors.borderSubtle)
                  : null,
            ),
            child: const SizedBox.square(dimension: 44),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        ],
      ),
    );
  }
}

class _TypographySpecimen extends StatelessWidget {
  const _TypographySpecimen();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your next move', style: text.displaySmall),
          const SizedBox(height: TracendSpacing.sm),
          Text('Maintain the approved plan', style: text.titleLarge),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Evidence is stable and no persistent change is proposed.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text('UPDATED 8:42 AM', style: text.labelMedium),
        ],
      ),
    );
  }
}

class _ActionSpecimen extends StatelessWidget {
  const _ActionSpecimen();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => _showSpecimenFeedback(context, 'Workout started'),
          icon: const Icon(CupertinoIcons.play_fill, size: 18),
          label: const Text('Start workout'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _showSpecimenFeedback(context, 'Evidence opened'),
          icon: const Icon(CupertinoIcons.eye, size: 18),
          label: const Text('View evidence'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        const FilledButton(onPressed: null, child: Text('Action unavailable')),
      ],
    );
  }

  void _showSpecimenFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SystemStates extends StatelessWidget {
  const _SystemStates();

  @override
  Widget build(BuildContext context) {
    return TracendCard(
      child: Column(
        children: const [
          _StateRow(
            icon: CupertinoIcons.checkmark_circle_fill,
            label: 'Ready',
            detail: 'Confirmed data is current',
          ),
          Divider(height: TracendSpacing.xl),
          _StateRow(
            icon: CupertinoIcons.wifi_slash,
            label: 'Offline',
            detail: 'Logging remains available',
          ),
          Divider(height: TracendSpacing.xl),
          _StateRow(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            label: 'Partial',
            detail: 'Sleep data is missing',
          ),
        ],
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.tracendColors.actionPrimary),
        const SizedBox(width: TracendSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
