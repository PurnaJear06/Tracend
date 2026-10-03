import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Read-only view of the confirmed facts that shape the plan and what the
/// Coach knows. Plan-changing edits stay approval-gated.
class ProfileGoalsScreen extends StatelessWidget {
  const ProfileGoalsScreen({required this.data, super.key});

  final Future<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile and goals')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: TracendLoader(semanticLabel: 'Loading your profile'),
            );
          }
          if (snapshot.hasError) {
            return const AccountDetailMessage(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'Profile could not load',
              detail:
                  'Your saved profile was not changed. Go back and try again.',
            );
          }
          final value = snapshot.data ?? const {};
          final profile = value['profile'] is Map
              ? Map<String, dynamic>.from(value['profile'] as Map)
              : const <String, dynamic>{};
          final goal = value['goal'] is Map
              ? Map<String, dynamic>.from(value['goal'] as Map)
              : const <String, dynamic>{};
          final plan = value['plan'] is Map
              ? Map<String, dynamic>.from(value['plan'] as Map)
              : const <String, dynamic>{};
          final planName = plan['training_plans'] is Map
              ? (plan['training_plans'] as Map)['title']?.toString()
              : null;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: TracendListRow.horizontalPadding,
                ),
                child: Text(
                  'These confirmed facts shape your plan and what the Coach knows about you.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SectionLabel('Goal'),
              AccountFactList(
                rows: {
                  'Primary goal': friendlyEnum(goal['goal_type']),
                  'Status': friendlyEnum(goal['status']),
                  'Active since': dateText(goal['activated_at']),
                },
              ),
              const SectionLabel('Training profile'),
              AccountFactList(
                rows: {
                  'Experience': friendlyEnum(profile['experience_level']),
                  'Height': profile['height_cm'] == null
                      ? 'Not recorded'
                      : '${profile['height_cm']} cm',
                  'Training days': trainingDaysText(profile['training_days']),
                  'Session length': profile['session_minutes'] == null
                      ? 'Not recorded'
                      : '${profile['session_minutes']} min',
                },
              ),
              if (profile['sex'] != null) ...[
                const SectionLabel('Onboarding answers'),
                AccountFactList(rows: onboardingAnswerRows(profile)),
              ],
              const SectionLabel('Approved plan'),
              AccountFactList(
                rows: {
                  'Plan': planName ?? 'No active plan',
                  'Version': plan['version_number'] == null
                      ? 'Not recorded'
                      : 'Version ${plan['version_number']}',
                  'Approved': dateText(plan['approved_at']),
                },
              ),
              const AccountFootnote(
                'These come from the onboarding answers you approved. Nothing about your plan changes without your approval.',
              ),
            ],
          );
        },
      ),
    ),
  );
}

const _activityLabels = {
  'mostly_sitting': 'Mostly sitting',
  'some_standing': 'On my feet some of the day',
  'mostly_standing': 'On my feet most of the day',
  'physical_labour': 'Physical work',
};

const _avoidLabels = {
  'squat': 'Squats',
  'lunge': 'Lunges and step-ups',
  'hinge': 'Deadlifts and hip hinges',
  'horizontal_push': 'Bench press and push-ups',
  'vertical_push': 'Overhead pressing',
  'horizontal_pull': 'Rows',
  'vertical_pull': 'Pull-ups and pulldowns',
};

/// The onboarding answers approval keeps on the profile, read-only.
Map<String, String> onboardingAnswerRows(Map<String, dynamic> profile) {
  String text(Object? value) {
    final trimmed = value?.toString().trim() ?? '';
    return trimmed.isEmpty ? 'None' : trimmed;
  }

  List<String> list(Object? value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];
  final equipment = list(profile['equipment']);
  final avoid = list(profile['avoid_patterns']);
  return {
    'Sex': friendlyEnum(profile['sex']),
    'Birth year': text(profile['birth_year']),
    'Daily activity':
        _activityLabels[profile['daily_activity']] ??
        friendlyEnum(profile['daily_activity']),
    'Equipment': equipment.isEmpty
        ? 'Bodyweight only'
        : equipment.map(friendlyEnum).join(', '),
    if ((profile['equipment_note']?.toString().trim() ?? '').isNotEmpty)
      'Equipment note': text(profile['equipment_note']),
    'Movements to avoid': avoid.isEmpty
        ? 'None'
        : avoid.map((pattern) => _avoidLabels[pattern] ?? pattern).join(', '),
    'Limitations': text(profile['limitations_note']),
    'Diet': text(profile['nutrition_note']),
  };
}
