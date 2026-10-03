import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// Read-only facts as one inset grouped list (DESIGN_SYSTEM.md §5.1): the
/// label on the left and the value on the right, as in iOS Settings. At large
/// text sizes or on a narrow phone the value moves under its label instead of
/// squeezing into a column.
class AccountFactList extends StatelessWidget {
  const AccountFactList({required this.rows, super.key});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => TracendGroupedList(
    children: [
      for (final entry in rows.entries)
        AccountFactRow(label: entry.key, value: entry.value),
    ],
  );
}

/// One label and value inside an [AccountFactList]. VoiceOver reads it as one
/// element ("Height, 182 cm").
class AccountFactRow extends StatelessWidget {
  const AccountFactRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    final labelText = Text(label, style: textTheme.bodyLarge);
    final valueStyle = textTheme.bodyLarge?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
            vertical: TracendSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                  constraints.maxWidth < 300;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelText,
                    const SizedBox(height: 2),
                    Text(value, style: valueStyle),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: labelText),
                  const SizedBox(width: TracendSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.55,
                    ),
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: valueStyle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A footnote under a grouped list, in the iOS position: small secondary
/// text inset to the list's rows.
class AccountFootnote extends StatelessWidget {
  const AccountFootnote(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      TracendListRow.horizontalPadding,
      TracendSpacing.xs,
      TracendListRow.horizontalPadding,
      0,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    ),
  );
}

/// Centered icon, title and detail for a load failure or an honest empty
/// state. The optional [action] slot carries a real retry control.
class AccountDetailMessage extends StatelessWidget {
  const AccountDetailMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TracendSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 56,
                  child: Icon(icon, size: 26, color: colors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: TracendSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// `snake_case` enum value → Title Case label.
String friendlyEnum(Object? value) => value == null
    ? 'Not recorded'
    : value
          .toString()
          .replaceAll('_', ' ')
          .split(' ')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
          )
          .join(' ');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A local calendar date with its year: "20 Aug 2026".
String fullDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// ISO timestamp → "20 Aug 2026", or `Not recorded`.
String dateText(Object? value) {
  if (value == null) return 'Not recorded';
  final date = DateTime.tryParse(value.toString());
  return date == null ? 'Not recorded' : fullDate(date);
}

/// 24-hour local time: "14:05".
String clockTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// ISO weekday list (1 = Monday) → `Mon, Wed, Fri` label.
String trainingDaysText(Object? value) {
  if (value is! List || value.isEmpty) return 'Not recorded';
  const days = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };
  return value.map((item) => days[(item as num).toInt()] ?? '?').join(', ');
}

/// A server dollar value with two decimals: `$1.00`, `$0.42`. A cost above
/// zero that would round to nothing reads `<$0.01`, never a misleading
/// `$0.00`. This only formats; the value always comes from the server.
String usdText(num value) {
  if (value > 0 && value < 0.005) return '<\$0.01';
  return '\$${value.toStringAsFixed(2)}';
}
