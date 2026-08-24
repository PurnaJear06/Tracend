import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// One append-only consent event from `consent_records`.
class ConsentRecord {
  const ConsentRecord({
    required this.consentType,
    required this.noticeVersion,
    required this.action,
    required this.source,
    required this.createdAt,
  });

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
    consentType: json['consent_type']?.toString() ?? '',
    noticeVersion: json['notice_version']?.toString() ?? '',
    action: json['action']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );

  final String consentType;
  final String noticeVersion;
  final String action;
  final String source;
  final DateTime? createdAt;
}

/// Read-only consent ledger: latest state per purpose (UX_FLOWS.md §13
/// "consent by purpose"). Records are append-only; the newest entry per
/// purpose is the current consent state.
class ConsentLedgerScreen extends StatefulWidget {
  const ConsentLedgerScreen({required this.load, super.key});

  /// Loader invoked once in `initState` so the FutureBuilder subscribes
  /// before the future can settle.
  final Future<List<ConsentRecord>> Function() load;

  @override
  State<ConsentLedgerScreen> createState() => _ConsentLedgerScreenState();
}

class _ConsentLedgerScreenState extends State<ConsentLedgerScreen> {
  late final Future<List<ConsentRecord>> _records;

  @override
  void initState() {
    super.initState();
    _records = widget.load();
  }

  static const _purposeLabels = <String, String>{
    'terms': 'Terms of use',
    'privacy': 'Privacy policy',
    'progress_photo_storage': 'Progress photo storage',
    'progress_photo_ai': 'Progress photo AI analysis',
    'notifications': 'Notifications',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Consent ledger')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<ConsentRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const AccountDetailMessage(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'Consent records could not load',
              detail:
                  'Your saved consent was not changed. Go back and try again.',
            );
          }
          final all = snapshot.data ?? const <ConsentRecord>[];
          if (all.isEmpty) {
            return const AccountDetailMessage(
              icon: CupertinoIcons.lock,
              title: 'No consent records yet',
              detail:
                  'Consent choices appear here after you accept the terms or change a privacy setting.',
            );
          }
          return _buildLedger(context, all);
        },
      ),
    ),
  );

  Widget _buildLedger(BuildContext context, List<ConsentRecord> records) {
    final latest = <String, ConsentRecord>{};
    for (final record in records) {
      final existing = latest[record.consentType];
      final at = record.createdAt;
      final existingAt = existing?.createdAt;
      if (existing == null ||
          (at != null && (existingAt == null || at.isAfter(existingAt)))) {
        latest[record.consentType] = record;
      }
    }
    final purposes = [
      ..._purposeLabels.keys,
      ...latest.keys.where((type) => !_purposeLabels.containsKey(type)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.md,
        TracendSpacing.gutter,
        TracendSpacing.xl,
      ),
      children: [
        Text(
          'Consent ledger',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: TracendSpacing.xs),
        const Text(
          'Append-only record of your consent choices. The latest entry per purpose is your current consent.',
        ),
        const SizedBox(height: TracendSpacing.lg),
        TracendCard(
          child: Column(
            children: [
              for (var i = 0; i < purposes.length; i++) ...[
                if (i > 0) const Divider(height: TracendSpacing.xl),
                _ConsentRow(
                  label:
                      _purposeLabels[purposes[i]] ?? friendlyEnum(purposes[i]),
                  record: latest[purposes[i]],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        const Text(
          'Withdrawing consent stops new processing for that purpose. Past processing remains recorded for audit.',
        ),
      ],
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.label, required this.record});

  final String label;
  final ConsentRecord? record;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final current = record;
    if (current == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'No record yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      );
    }
    final granted = current.action == 'granted';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                '${granted ? 'Granted' : 'Withdrawn'} · '
                '${dateText(current.createdAt)} · ${current.noticeVersion} · '
                '${_sourceText(current.source)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: TracendSpacing.sm),
        TracendPill(
          label: granted ? 'Granted' : 'Withdrawn',
          icon: granted
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.slash_circle_fill,
          color: granted ? colors.stateStable : colors.stateAttention,
          compact: true,
        ),
      ],
    );
  }

  String _sourceText(String source) => switch (source) {
    'ios_app' => 'iOS app',
    'owner_development' => 'owner development',
    _ => friendlyEnum(source),
  };
}
