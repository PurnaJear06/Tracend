import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// One consent event from `consent_records`. Records are only ever added; the
/// newest one for a purpose is the choice that applies now.
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

  bool get granted => action == 'granted';
}

/// Read-only consent history (UX_FLOWS.md §13): the current choice for each
/// purpose, with the date it was made and, as secondary text, the notice
/// version it answered. Choices change in the flow that owns each purpose.
class ConsentHistoryScreen extends StatefulWidget {
  const ConsentHistoryScreen({required this.load, super.key});

  /// Loader invoked once in `initState` so the FutureBuilder subscribes
  /// before the future can settle.
  final Future<List<ConsentRecord>> Function() load;

  @override
  State<ConsentHistoryScreen> createState() => _ConsentHistoryScreenState();
}

class _ConsentHistoryScreenState extends State<ConsentHistoryScreen> {
  late final Future<List<ConsentRecord>> _records;

  @override
  void initState() {
    super.initState();
    _records = widget.load();
  }

  static const _purposeLabels = <String, String>{
    'terms': 'Terms of use',
    'privacy': 'Privacy policy',
    'ai_coaching': 'AI coaching',
    'progress_photo_storage': 'Progress photo storage',
    'progress_photo_ai': 'Progress photo AI analysis',
    'meal_photo_ai': 'Meal photo AI analysis',
    'notifications': 'Notifications',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Consent history')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<ConsentRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: TracendLoader(semanticLabel: 'Loading consent history'),
            );
          }
          if (snapshot.hasError) {
            return const AccountDetailMessage(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'Consent history could not load',
              detail:
                  'Your saved consent was not changed. Go back and try again.',
            );
          }
          final all = snapshot.data ?? const <ConsentRecord>[];
          if (all.isEmpty) {
            return const AccountDetailMessage(
              icon: CupertinoIcons.lock,
              title: 'No consent choices yet',
              detail:
                  'Choices appear here after you accept the terms or change a privacy setting.',
            );
          }
          return _history(context, all);
        },
      ),
    ),
  );

  Widget _history(BuildContext context, List<ConsentRecord> records) {
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
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        TracendSpacing.xs,
        gutter,
        TracendSpacing.xxl,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TracendListRow.horizontalPadding,
            0,
            TracendListRow.horizontalPadding,
            TracendSpacing.md,
          ),
          child: Text(
            'The choice that applies now for each purpose, and when you made it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        TracendGroupedList(
          children: [
            for (final purpose in purposes)
              consentHistoryRow(
                context,
                label: _purposeLabels[purpose] ?? friendlyEnum(purpose),
                record: latest[purpose],
              ),
          ],
        ),
        const AccountFootnote(
          'Withdrawing consent stops new processing for that purpose. Earlier '
          'processing stays on record.',
        ),
      ],
    );
  }
}

/// One purpose: the choice and its date, then the notice version and where
/// the choice was made as secondary text.
TracendListRow consentHistoryRow(
  BuildContext context, {
  required String label,
  required ConsentRecord? record,
}) {
  final colors = context.tracendColors;
  if (record == null) {
    return TracendListRow(
      title: label,
      subtitle: 'No choice recorded yet',
      leading: const TracendRowIcon(icon: CupertinoIcons.circle),
      semanticLabel: '$label. No choice recorded yet.',
    );
  }
  final at = record.createdAt;
  final choice =
      '${record.granted ? 'Granted' : 'Withdrawn'}'
      '${at == null ? '' : ' ${fullDate(at)}'}';
  final secondary = [
    if (record.noticeVersion.isNotEmpty) 'Version ${record.noticeVersion}',
    consentSourceText(record.source),
  ].join(' · ');
  return TracendListRow(
    title: label,
    subtitle: '$choice\n$secondary',
    leading: TracendRowIcon(
      icon: record.granted
          ? CupertinoIcons.checkmark_alt
          : CupertinoIcons.minus,
      color: record.granted ? colors.stateStable : null,
    ),
    semanticLabel: '$label. $choice. $secondary.',
  );
}

/// Where a consent choice was made, in words.
String consentSourceText(String source) => switch (source) {
  'ios_app' => 'iOS app',
  'owner_development' => 'Set up during testing',
  _ => friendlyEnum(source),
};
