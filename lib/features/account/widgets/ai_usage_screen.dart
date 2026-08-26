import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Sanitized, user-scoped AI usage detail screen (UX_FLOWS.md §13).
///
/// Every value binds a real `get_my_ai_usage` / `get_my_ai_budget_state`
/// field merged by [CoachRepository.loadUsage] — thresholds and limits are
/// rendered from the RPC response, never hardcoded. Token counts, per-feature
/// breakdowns, and period toggles do not exist in any RPC, so they are not
/// shown. API keys, prompts, provider request identifiers, raw errors, and
/// cross-user totals never appear here.
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
            return const Center(child: CircularProgressIndicator());
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
          return _buildContent(context, snapshot.data ?? const {});
        },
      ),
    ),
  );

  Widget _buildContent(BuildContext context, Map<String, dynamic> usage) {
    final colors = context.tracendColors;
    final cost = (usage['estimated_cost_usd'] as num?)?.toDouble() ?? 0;
    final hardStop = (usage['hard_stop_usd'] as num?)?.toDouble();
    final warningAt = (usage['warning_threshold_usd'] as num?)?.toDouble();
    final dailyLimit = (usage['daily_limit'] as num?)?.toInt();
    final today = (usage['today_requests'] as num?)?.toInt() ?? 0;
    final successful = (usage['successful_runs'] as num?)?.toInt() ?? 0;
    final failed = (usage['failed_runs'] as num?)?.toInt() ?? 0;
    final blocked = usage['blocked'] == true;
    final warning = usage['warning'] == true;
    final hasBudget = hardStop != null;
    final noRuns = successful == 0 && failed == 0 && cost == 0;

    final rows = <String, String>{
      if (dailyLimit != null) 'Requests today': '$today of $dailyLimit',
      'Successful this month': '$successful',
      'Failed this month': '$failed',
      if (warningAt != null) 'Warning threshold': usdText(warningAt),
      if (hardStop != null) 'Monthly hard stop': usdText(hardStop),
      'Service': blocked
          ? 'Paused at safety limit'
          : hasBudget
          ? 'Available'
          : 'Estimates only',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.md,
        TracendSpacing.gutter,
        TracendSpacing.xl,
      ),
      children: [
        Text('My AI usage', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: TracendSpacing.xs),
        const Text(
          'Sanitized usage from the server. Provider keys, prompts, and private health values never appear here.',
        ),
        const SizedBox(height: TracendSpacing.lg),
        PremiumGradientCard(
          glow: true,
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (blocked)
                TracendPill(
                  label: 'Paused at safety limit',
                  icon: CupertinoIcons.pause_circle_fill,
                  color: colors.stateDanger,
                )
              else if (warning)
                TracendPill(
                  label: 'Approaching limit',
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  color: colors.stateAttention,
                )
              else if (hasBudget)
                TracendPill(
                  label: 'Available',
                  icon: CupertinoIcons.check_mark_circled_solid,
                  color: colors.stateStable,
                ),
              if (hasBudget) const SizedBox(height: TracendSpacing.sm),
              Text(
                '\$${cost.toStringAsFixed(4)}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                hasBudget
                    ? 'estimated this month · of ${usdText(hardStop)} hard stop'
                    : 'estimated this month',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (hasBudget && hardStop > 0) ...[
                const SizedBox(height: TracendSpacing.sm),
                Semantics(
                  label:
                      'Monthly AI budget usage '
                      '${(cost / hardStop * 100).clamp(0, 100).toStringAsFixed(0)} percent',
                  child: LinearProgressIndicator(
                    value: (cost / hardStop).clamp(0, 1),
                  ),
                ),
              ],
              if (noRuns) ...[
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  'No AI runs recorded this month.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SectionLabel('This month'),
        TracendCard(child: DetailRows(rows: rows)),
        const SizedBox(height: TracendSpacing.sm),
        const Text(
          'Operational estimates from the AI service budget — not an invoice or a subscription charge.',
        ),
        const SizedBox(height: TracendSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(CupertinoIcons.refresh, size: 18),
            label: const Text('Refresh usage'),
          ),
        ),
      ],
    );
  }
}
