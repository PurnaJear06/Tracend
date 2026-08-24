import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Read-only view of the confirmed facts that shape the plan and every
/// Coach context snapshot. Plan-changing edits stay approval-gated.
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
            return const Center(child: CircularProgressIndicator());
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              TracendSpacing.gutter,
              TracendSpacing.md,
              TracendSpacing.gutter,
              TracendSpacing.xl,
            ),
            children: [
              Text(
                'Your coaching foundation',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: TracendSpacing.xs),
              const Text(
                'These confirmed facts shape your plan and every Coach context snapshot.',
              ),
              const SectionLabel('Goal'),
              PremiumGradientCard(
                glow: true,
                child: DetailRows(
                  rows: {
                    'Primary goal': friendlyEnum(goal['goal_type']),
                    'Status': friendlyEnum(goal['status']),
                    'Active since': dateText(goal['activated_at']),
                  },
                ),
              ),
              const SectionLabel('Training profile'),
              TracendCard(
                child: DetailRows(
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
              ),
              const SectionLabel('Approved plan'),
              TracendCard(
                child: DetailRows(
                  rows: {
                    'Plan': planName ?? 'No active plan',
                    'Version': plan['version_number'] == null
                        ? '—'
                        : 'v${plan['version_number']}',
                    'Approved': dateText(plan['approved_at']),
                  },
                ),
              ),
              const SizedBox(height: TracendSpacing.sm),
              const Text(
                'Plan-changing edits remain approval-gated. Ask Coach for a proposal when you want to change your goal or ongoing plan.',
              ),
            ],
          );
        },
      ),
    ),
  );
}
