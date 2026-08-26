import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// One navigation or status row inside an Account card.
///
/// The chevron renders only when [onTap] is provided — rows without a
/// destination are display-only facts (no dead affordances).
class AccountRow extends StatelessWidget {
  const AccountRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.detailColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final Color? detailColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      button: onTap != null,
      label: '$title. $detail.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TracendRadii.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.actionPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TracendRadii.control),
                ),
                child: Icon(icon, size: 18, color: colors.actionPrimary),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: detailColor ?? colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: TracendSpacing.xs),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Label/value rows for read-only detail cards. Values use tabular figures
/// so changing numbers never shift layout.
class DetailRows extends StatelessWidget {
  const DetailRows({required this.rows, super.key});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: TracendSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(rows.keys.elementAt(i))),
            const SizedBox(width: TracendSpacing.sm),
            Flexible(
              child: Text(
                rows.values.elementAt(i),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

/// Centered icon + title + detail message for loading failures and honest
/// empty states. The optional [action] slot carries a real retry control.
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: TracendSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: TracendSpacing.xs),
          Text(detail, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: TracendSpacing.md),
            action!,
          ],
        ],
      ),
    ),
  );
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

/// ISO timestamp → local `d/m/yyyy`, or `Not recorded`.
String dateText(Object? value) {
  if (value == null) return 'Not recorded';
  final date = DateTime.tryParse(value.toString())?.toLocal();
  return date == null
      ? 'Not recorded'
      : '${date.day}/${date.month}/${date.year}';
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

/// `$3` for whole-dollar values, `$2.50` for fractional ones — server
/// thresholds are RPC-bound and may change, so never round blindly.
String usdText(num value) => value == value.roundToDouble()
    ? '\$${value.toStringAsFixed(0)}'
    : '\$${value.toStringAsFixed(2)}';
