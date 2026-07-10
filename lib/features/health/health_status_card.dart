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
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.heart_fill, color: color),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text(
                  status.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TracendPill(
                label: _label(status.state),
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(status.detail, style: Theme.of(context).textTheme.bodyMedium),
          if (!widget.compact && status.availableMetrics.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              '${status.availableMetrics.length} data categories found in the last sync',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Found: ${(status.availableMetrics.toList()..sort((a, b) => a.index.compareTo(b.index))).map((metric) => metric.label).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (status.availableMetrics.length < HealthMetric.values.length)
              Text(
                'No recent samples: ${HealthMetric.values.where((metric) => !status.availableMetrics.contains(metric)).map((metric) => metric.label).join(', ')}. This can mean no data was recorded, or read access is unavailable.',
                style: Theme.of(context).textTheme.bodySmall,
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
                    : 'Refresh health summary',
              ),
            ),
          ),
          if (!widget.compact)
            Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.xs),
              child: Text(
                'Optional. Tracend requests read access only and stores daily summaries, not raw samples.',
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
}
