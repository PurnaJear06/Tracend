import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';
import 'package:tracend/shared/widgets/trajectory_trend.dart';

/// Fixture 7-day HRV history for the trend specimen (dev-only sample data).
final HealthHistory _galleryHistory = HealthHistory([
  for (var i = 6; i >= 0; i--)
    HealthDay(
      date: DateTime(2026, 8, 24).subtract(Duration(days: i)),
      presentMetrics: const {HealthMetric.hrvSdnn},
      hrvSdnnMs: [42, 45, 44, 48, 47, 51, 53][6 - i].toDouble(),
    ),
]);

/// The development-only component gallery. It opens in [themeMode] and
/// offers a System / Light / Dark switch so every component can be checked
/// in both themes.
class ComponentGalleryApp extends StatefulWidget {
  const ComponentGalleryApp({this.themeMode = ThemeMode.system, super.key});

  final ThemeMode themeMode;

  @override
  State<ComponentGalleryApp> createState() => _ComponentGalleryAppState();
}

class _ComponentGalleryAppState extends State<ComponentGalleryApp> {
  late ThemeMode _mode = widget.themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracend component gallery',
      debugShowCheckedModeBanner: false,
      theme: TracendTheme.light,
      darkTheme: TracendTheme.dark,
      themeMode: _mode,
      home: ComponentGalleryScreen(
        themeMode: _mode,
        onThemeModeChanged: (mode) => setState(() => _mode = mode),
      ),
    );
  }
}

class ComponentGalleryScreen extends StatelessWidget {
  const ComponentGalleryScreen({
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TracendScrollView(
        title: 'Component gallery',
        subtitle: 'Graphite + signal lime · UI reference',
        children: [
          const _GalleryNote(),
          const SectionLabel('Theme'),
          TracendSegmentedControl<ThemeMode>(
            segments: const [
              (ThemeMode.system, 'System'),
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ],
            selected: themeMode,
            onChanged: onThemeModeChanged,
          ),
          const SectionLabel('Color roles'),
          const _ColorRoles(),
          const SectionLabel('Typography'),
          const _TypographySpecimen(),
          const SectionLabel('Actions'),
          const _ActionSpecimen(),
          const SectionLabel('Sheets and confirmations'),
          const _OverlaySpecimen(),
          const SectionLabel('Pressable'),
          const _PressableSpecimen(),
          const SectionLabel('Status chips'),
          const _StatusChipSpecimen(),
          const SectionLabel('Exercises', value: '16 sets'),
          const _GroupedListSpecimen(),
          const SectionLabel('Loading'),
          const _SkeletonSpecimen(),
          const SectionLabel('Evidence'),
          TrajectoryTrend(history: _galleryHistory),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.scope, color: context.tracendColors.textPrimary),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Text(
              'A development-only surface for checking tokens, components, '
              'Dynamic Type, contrast, motion and semantic reading order.',
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
              label: 'Signal lime · now and selected',
              color: colors.accentSignal,
              width: width,
            ),
            _ColorRole(
              label: 'Primary action',
              color: colors.actionPrimary,
              width: width,
            ),
            _ColorRole(label: 'Good', color: colors.stateStable, width: width),
            _ColorRole(
              label: 'Caution',
              color: colors.accentAmber,
              width: width,
            ),
            _ColorRole(
              label: 'Low',
              color: colors.stateAttention,
              width: width,
            ),
            _ColorRole(
              label: 'Raised surface',
              color: colors.surfaceRaised,
              width: width,
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
  });

  final String label;
  final Color color;
  final double width;

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
    final colors = context.tracendColors;
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
          const SizedBox(height: TracendSpacing.sm),
          Text(
            '82.5 kg × 6',
            style: TracendTheme.numeric(colors, fontSize: 28),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text('Updated 8:42 AM', style: text.labelMedium),
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
          onPressed: () {
            TracendHaptics.heavy();
            TracendToast.show(
              context,
              'Workout started',
              icon: CupertinoIcons.play_fill,
            );
          },
          icon: const Icon(CupertinoIcons.play_fill, size: 18),
          label: const Text('Start workout'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => TracendToast.show(
            context,
            'Evidence opened',
            icon: CupertinoIcons.eye,
          ),
          icon: const Icon(CupertinoIcons.eye, size: 18),
          label: const Text('View evidence'),
        ),
        const SizedBox(height: TracendSpacing.sm),
        const FilledButton(onPressed: null, child: Text('Action unavailable')),
      ],
    );
  }
}

class _OverlaySpecimen extends StatelessWidget {
  const _OverlaySpecimen();

  Future<void> _openSheet(BuildContext context) => showTracendSheet<void>(
    context,
    title: 'Training load',
    subtitle: 'How much you have trained lately',
    builder: (sheetContext) => const _SheetBody(),
  );

  Future<void> _openDetentSheet(BuildContext context) => showTracendSheet<void>(
    context,
    title: 'Bench press',
    subtitle: 'Exercise 1 of 5',
    detents: const [0.5, 0.92],
    builder: (sheetContext) => const _SheetBody(rows: 8),
  );

  Future<void> _openActionSheet(BuildContext context) async {
    final choice = await showTracendActionSheet<String>(
      context,
      title: 'Leave this workout?',
      message: '3 sets are saved on your phone. You can carry on later today.',
      actions: const [
        TracendSheetAction(
          label: 'Save and leave',
          value: 'Saved for later',
          isDefault: true,
        ),
        TracendSheetAction(
          label: 'Discard workout',
          value: 'Workout discarded',
          destructive: true,
        ),
      ],
    );
    if (choice != null && context.mounted) {
      TracendToast.show(context, choice);
    }
  }

  Future<void> _openConfirm(BuildContext context) async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete this thread?',
      message: 'The conversation is removed from this device and your account.',
      confirmLabel: 'Delete thread',
      destructive: true,
    );
    if (confirmed && context.mounted) {
      TracendToast.show(context, 'Thread deleted', icon: CupertinoIcons.trash);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TracendGroupedList(
      children: [
        TracendListRow(
          title: 'Sheet',
          subtitle: 'Header, handle, swipe to close',
          leading: const TracendRowIcon(icon: CupertinoIcons.square_stack),
          onTap: () => _openSheet(context),
        ),
        TracendListRow(
          title: 'Sheet with detents',
          subtitle: 'Opens at half height, snaps to full',
          leading: const TracendRowIcon(
            icon: CupertinoIcons.arrow_up_down_square,
          ),
          onTap: () => _openDetentSheet(context),
        ),
        TracendListRow(
          title: 'Action sheet',
          subtitle: 'Related choices with a destructive one',
          leading: const TracendRowIcon(icon: CupertinoIcons.list_bullet),
          onTap: () => _openActionSheet(context),
        ),
        TracendListRow(
          title: 'Destructive confirm',
          subtitle: 'Cancel is the default',
          leading: TracendRowIcon(
            icon: CupertinoIcons.trash,
            color: context.tracendColors.stateDanger,
          ),
          onTap: () => _openConfirm(context),
        ),
        TracendListRow(
          title: 'Toast',
          subtitle: 'Transient confirmation at the top',
          leading: const TracendRowIcon(icon: CupertinoIcons.bell),
          onTap: () => TracendToast.show(context, 'Check-in saved'),
        ),
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sheets hold one focused task. Swipe down, tap outside or use the '
          'close button to leave.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.md),
        TracendGroupedList(
          children: [
            for (var i = 1; i <= rows; i++)
              TracendListRow(
                title: 'Set $i',
                subtitle: '80 kg × 8',
                trailing: Text(
                  'RPE 8',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: TracendSpacing.md),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _PressableSpecimen extends StatelessWidget {
  const _PressableSpecimen();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: () => TracendToast.show(context, 'Readiness opened'),
      haptic: TracendHaptics.light,
      child: TracendCard(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.stateGoodTint,
                borderRadius: BorderRadius.circular(TracendRadii.control),
              ),
              child: Icon(
                CupertinoIcons.bolt_fill,
                size: 18,
                color: colors.stateStable,
              ),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ready to train', style: text.titleSmall),
                  Text(
                    'Based on last night and your 30-day normal',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChipSpecimen extends StatelessWidget {
  const _StatusChipSpecimen();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: TracendSpacing.xs,
      runSpacing: TracendSpacing.xs,
      children: [
        StatusChip(
          label: 'Saved and synced',
          icon: CupertinoIcons.check_mark_circled_solid,
          tone: StatusTone.good,
        ),
        StatusChip(
          label: 'Sync pending',
          icon: CupertinoIcons.wifi_slash,
          tone: StatusTone.caution,
        ),
        StatusChip(
          label: 'Sync failed',
          icon: CupertinoIcons.exclamationmark_circle,
          tone: StatusTone.low,
        ),
        StatusChip(
          label: 'Autosave is ready',
          icon: CupertinoIcons.arrow_2_circlepath,
        ),
        StatusChip(
          label: 'New best',
          icon: CupertinoIcons.star_fill,
          tone: StatusTone.signal,
        ),
      ],
    );
  }
}

class _GroupedListSpecimen extends StatelessWidget {
  const _GroupedListSpecimen();

  @override
  Widget build(BuildContext context) {
    final trailing = Theme.of(context).textTheme.bodySmall;
    return TracendGroupedList(
      children: [
        TracendListRow(
          title: 'Bench press',
          subtitle: '4 × 6–8 · rest 2 min',
          leading: const TracendRowIcon(icon: CupertinoIcons.number),
          trailing: Text('80 kg', style: trailing),
          onTap: () => TracendToast.show(context, 'Bench press opened'),
        ),
        TracendListRow(
          title: 'Incline dumbbell press',
          subtitle: '3 × 10',
          leading: const TracendRowIcon(icon: CupertinoIcons.number),
          trailing: Text('26 kg', style: trailing),
          onTap: () => TracendToast.show(context, 'Incline press opened'),
        ),
        const TracendListRow(
          title: 'Cable fly',
          subtitle: '3 × 12 · not tappable',
        ),
      ],
    );
  }
}

class _SkeletonSpecimen extends StatelessWidget {
  const _SkeletonSpecimen();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading example',
      container: true,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TracendSkeleton.block(height: 96),
          SizedBox(height: TracendSpacing.sm),
          TracendCard(
            child: Column(
              children: [TracendSkeleton.row(), TracendSkeleton.row(lines: 1)],
            ),
          ),
          SizedBox(height: TracendSpacing.sm),
          TracendSkeleton.line(widthFactor: 0.8),
          SizedBox(height: TracendSpacing.xs),
          TracendSkeleton.line(widthFactor: 0.55),
        ],
      ),
    );
  }
}

class _SystemStates extends StatelessWidget {
  const _SystemStates();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return TracendCard(
      child: Column(
        children: [
          _StateRow(
            icon: CupertinoIcons.checkmark_circle_fill,
            color: colors.stateStable,
            label: 'Ready',
            detail: 'Confirmed data is current',
          ),
          const Divider(height: TracendSpacing.xl),
          _StateRow(
            icon: CupertinoIcons.wifi_slash,
            color: colors.accentAmber,
            label: 'Offline',
            detail: 'Logging remains available',
          ),
          const Divider(height: TracendSpacing.xl),
          _StateRow(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            color: colors.stateAttention,
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
    required this.color,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
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
