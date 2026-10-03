import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// This month's AI usage as the server reports it (`get_my_ai_usage` merged
/// with `get_my_ai_budget_state` by [CoachRepository.loadUsage]). Every
/// threshold and flag is a server value; nothing here is a hard-coded limit.
@immutable
class AiUsageSummary {
  const AiUsageSummary({
    required this.cost,
    required this.successful,
    required this.failed,
    required this.today,
    required this.blocked,
    required this.warning,
    this.warningAt,
    this.hardStop,
    this.dailyLimit,
  });

  factory AiUsageSummary.fromJson(Map<String, dynamic> usage) => AiUsageSummary(
    cost: (usage['estimated_cost_usd'] as num?)?.toDouble() ?? 0,
    successful: (usage['successful_runs'] as num?)?.toInt() ?? 0,
    failed: (usage['failed_runs'] as num?)?.toInt() ?? 0,
    today: (usage['today_requests'] as num?)?.toInt() ?? 0,
    blocked: usage['blocked'] == true,
    warning: usage['warning'] == true,
    warningAt: (usage['warning_threshold_usd'] as num?)?.toDouble(),
    hardStop: (usage['hard_stop_usd'] as num?)?.toDouble(),
    dailyLimit: (usage['daily_limit'] as num?)?.toInt(),
  );

  final double cost;
  final int successful;
  final int failed;
  final int today;
  final bool blocked;
  final bool warning;
  final double? warningAt;
  final double? hardStop;
  final int? dailyLimit;

  bool get hasBudget => hardStop != null;
  bool get noRuns => successful == 0 && failed == 0 && cost == 0;

  /// The service state in words.
  String get serviceText => blocked
      ? 'Paused at the monthly limit'
      : warning
      ? 'Approaching the monthly limit'
      : hasBudget
      ? 'Available'
      : 'Estimates only';

  /// One line that places this month's cost against the server limits, for
  /// the Account row: "$0.42 of $2.00 · warning at $1.00".
  String get accountLine {
    final spent = usdText(cost);
    final stop = hardStop;
    final warn = warningAt;
    if (blocked && stop != null) {
      return '$spent · paused at the ${usdText(stop)} limit · plans and logging still work';
    }
    if (warning && stop != null) {
      return '$spent · approaching the ${usdText(stop)} limit';
    }
    if (stop != null && warn != null) {
      return '$spent of ${usdText(stop)} · warning at ${usdText(warn)}';
    }
    if (stop != null) return '$spent of ${usdText(stop)} monthly limit';
    final runs = successful + failed;
    return '$spent estimate · $runs ${runs == 1 ? 'request' : 'requests'}';
  }
}

/// Sanitized, user-scoped AI usage detail (UX_FLOWS.md §13).
///
/// Token counts, per-feature breakdowns and period toggles do not exist in
/// any RPC, so they are not shown. API keys, prompts, provider request
/// identifiers, raw errors and cross-user totals never appear here.
class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({required this.coach, this.initialUsage, super.key});

  final CoachRepository coach;

  /// Already-fetched usage from the Account row; avoids a duplicate RPC on
  /// open. Refresh always refetches.
  final Map<String, dynamic>? initialUsage;

  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  late Future<Map<String, dynamic>> _usage;

  @override
  void initState() {
    super.initState();
    _usage = widget.initialUsage == null
        ? widget.coach.loadUsage()
        : Future.value(widget.initialUsage);
  }

  void _refresh() {
    setState(() {
      _usage = widget.coach.loadUsage();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI usage')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _usage,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: TracendLoader(semanticLabel: 'Loading AI usage'),
            );
          }
          if (snapshot.hasError) {
            return AccountDetailMessage(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'Usage could not load',
              detail:
                  'This does not affect your approved plan or manual logging.',
              action: OutlinedButton(
                onPressed: _refresh,
                child: const Text('Try again'),
              ),
            );
          }
          return _content(
            context,
            AiUsageSummary.fromJson(snapshot.data ?? const {}),
          );
        },
      ),
    ),
  );

  Widget _content(BuildContext context, AiUsageSummary usage) {
    final textTheme = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < 375 ? TracendSpacing.md : TracendSpacing.gutter;
    final stop = usage.hardStop;
    final warn = usage.warningAt;
    final rows = <String, String>{
      if (usage.dailyLimit != null)
        'Requests today': '${usage.today} of ${usage.dailyLimit}',
      'Successful this month': '${usage.successful}',
      'Failed this month': '${usage.failed}',
      if (warn != null) 'Warning at': usdText(warn),
      if (stop != null) 'Monthly limit': usdText(stop),
      'Service': usage.serviceText,
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        TracendSpacing.xs,
        gutter,
        TracendSpacing.xxl,
      ),
      children: [
        TracendCard(
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (usage.blocked)
                const StatusChip(
                  label: 'Paused at the monthly limit',
                  icon: CupertinoIcons.pause_circle_fill,
                  tone: StatusTone.low,
                )
              else if (usage.warning)
                const StatusChip(
                  label: 'Approaching the monthly limit',
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  tone: StatusTone.caution,
                )
              else if (usage.hasBudget)
                const StatusChip(
                  label: 'Available',
                  icon: CupertinoIcons.check_mark_circled_solid,
                  tone: StatusTone.good,
                ),
              if (usage.hasBudget) const SizedBox(height: TracendSpacing.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  usdText(usage.cost),
                  style: TracendTheme.numeric(
                    context.tracendColors,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                stop == null
                    ? 'Estimated this month'
                    : 'Estimated this month, of ${usdText(stop)}',
                style: textTheme.bodyMedium,
              ),
              if (stop != null && stop > 0) ...[
                const SizedBox(height: TracendSpacing.md),
                AiUsageMeter(
                  cost: usage.cost,
                  hardStop: stop,
                  warningAt: warn,
                  blocked: usage.blocked,
                  warning: usage.warning,
                ),
                const SizedBox(height: TracendSpacing.xs),
                Text(
                  [
                    if (warn != null) 'Warning at ${usdText(warn)}',
                    'Stops at ${usdText(stop)}',
                  ].join(' · '),
                  style: textTheme.bodySmall,
                ),
              ],
              if (usage.noRuns) ...[
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  'No AI runs recorded this month.',
                  style: textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SectionLabel('This month'),
        AccountFactList(rows: rows),
        const AccountFootnote(
          'Operational estimates from the AI service budget, not an invoice '
          'or a subscription charge. Provider keys, prompts and your health '
          'values never appear here.',
        ),
        const SizedBox(height: TracendSpacing.lg),
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(CupertinoIcons.refresh, size: 18),
          label: const Text('Refresh usage'),
        ),
      ],
    );
  }
}

/// This month's cost on a track that ends at the server's monthly limit,
/// with a tick at the warning threshold. Color follows the server's state
/// (caution when warned, danger when paused) and the label says it in words.
class AiUsageMeter extends StatelessWidget {
  const AiUsageMeter({
    required this.cost,
    required this.hardStop,
    required this.blocked,
    required this.warning,
    this.warningAt,
    super.key,
  });

  final double cost;
  final double hardStop;
  final double? warningAt;
  final bool blocked;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final fraction = (cost / hardStop).clamp(0.0, 1.0);
    final tick = warningAt == null
        ? null
        : (warningAt! / hardStop).clamp(0.0, 1.0);
    final fill = blocked
        ? colors.stateDanger
        : warning
        ? colors.accentAmber
        : colors.actionPrimary;
    final percent = (fraction * 100).round();
    return Semantics(
      container: true,
      label:
          'AI usage this month: ${usdText(cost)} of ${usdText(hardStop)}, '
          '$percent percent'
          '${warningAt == null ? '' : '. Warning at ${usdText(warningAt!)}'}',
      excludeSemantics: true,
      child: SizedBox(
        height: 16,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(TracendRadii.pill),
                  ),
                ),
                if (fraction > 0)
                  Container(
                    width: (width * fraction).clamp(8.0, width),
                    height: 8,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(TracendRadii.pill),
                    ),
                  ),
                if (tick != null)
                  Positioned(
                    left: (width * tick - 1).clamp(0.0, width - 2),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: colors.textSecondary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
