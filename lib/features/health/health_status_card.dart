import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class HealthStatusCard extends StatefulWidget {
  const HealthStatusCard({
    required this.repository,
    this.compact = false,
    this.onSynced,
    super.key,
  });

  final HealthRepository repository;
  final bool compact;
  final VoidCallback? onSynced;

  @override
  State<HealthStatusCard> createState() => _HealthStatusCardState();
}

class _HealthStatusCardState extends State<HealthStatusCard> {
  HealthSyncStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await widget.repository.loadStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await widget.repository.connectAndSync();
      if (mounted) {
        setState(() => _status = status);
        widget.onSynced?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Apple Health could not sync. Manual tracking is still available.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status =
        _status ??
        const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    final color = switch (status.state) {
      HealthConnectionState.connected => context.tracendColors.stateStable,
      HealthConnectionState.partial => context.tracendColors.actionPrimary,
      HealthConnectionState.stale => context.tracendColors.stateAttention,
      HealthConnectionState.manualOnly ||
      HealthConnectionState.unavailable => context.tracendColors.textSecondary,
    };
    final available = status.availableMetrics.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final missing = HealthMetric.values
        .where((metric) => !status.availableMetrics.contains(metric))
        .toList();
    final refreshed = const {
      HealthConnectionState.connected,
      HealthConnectionState.partial,
    }.contains(status.state);
    return TracendCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.heart_fill, color: color),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text(
                  refreshed ? 'Health data refreshed' : status.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TracendPill(
                label: refreshed
                    ? '${available.length} of ${HealthMetric.values.length}'
                    : _label(status.state),
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            refreshed
                ? available.isEmpty
                      ? 'No recent Apple Health values were found. Coaching continues with your manual entries.'
                      : '${available.map((metric) => metric.label).join(', ')} ${available.length == 1 ? 'is' : 'are'} ready for coaching.'
                : status.detail,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!widget.compact && status.availableMetrics.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Wrap(
              spacing: TracendSpacing.xs,
              runSpacing: TracendSpacing.xs,
              children: [
                for (final metric in available)
                  _AvailableSignal(metric: metric),
              ],
            ),
            if (missing.isNotEmpty)
              Material(
                color: Colors.transparent,
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const PageStorageKey('health-missing-signals'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('${missing.length} signals not found'),
                    subtitle: const Text('This does not block your coaching'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${missing.map((metric) => metric.label).join(', ')} had no recent values. Apple Health may not contain them, or Tracend may not have read access.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (!widget.compact &&
              status.state == HealthConnectionState.manualOnly) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Reads: steps, active energy, sleep, workouts, weight, resting heart rate and HRV (SDNN).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.tracendColors.stateAttention,
              ),
            ),
          ],
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.refresh, size: 18),
              label: Text(
                status.state == HealthConnectionState.manualOnly
                    ? 'Connect Apple Health'
                    : 'Refresh Apple Health',
              ),
            ),
          ),
          if (!widget.compact && status.lastSuccessfulSync != null)
            Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.xs),
              child: Text(
                'Last refreshed ${_time(status.lastSuccessfulSync!.toLocal())} · read-only summaries',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  String _label(HealthConnectionState state) => switch (state) {
    HealthConnectionState.connected => 'Connected',
    HealthConnectionState.partial => 'Partial',
    HealthConnectionState.stale => 'Stale',
    HealthConnectionState.manualOnly => 'Manual',
    HealthConnectionState.unavailable => 'Unavailable',
  };

  String _time(DateTime value) =>
      '${value.day}/${value.month} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _AvailableSignal extends StatelessWidget {
  const _AvailableSignal({required this.metric});
  final HealthMetric metric;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tracendColors.stateStable.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        metric.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.tracendColors.stateStable,
        ),
      ),
    ),
  );
}
