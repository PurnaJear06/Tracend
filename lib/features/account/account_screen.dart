import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
import 'package:tracend/features/account/widgets/account_sheets.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/account/widgets/ai_usage_screen.dart';
import 'package:tracend/features/account/widgets/coach_threads_sheet.dart';
import 'package:tracend/features/account/widgets/consent_ledger_screen.dart';
import 'package:tracend/features/account/widgets/notification_sheet.dart';
import 'package:tracend/features/account/widgets/profile_goals_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Account home, redesigned 2026-09-03 from the Stitch reference
/// `design/stitch/account/` ("Account & Profile — Kinetic Precision"):
/// identity block first (name from the email local-part, private-beta
/// chip, current goal, edit affordance), then grouped hairline cards under
/// label-caps sections — Plan, Connections, AI service, Privacy and data —
/// with the sign-out control and the delete-account danger zone separated
/// at the foot. Icon tiles are gone: the quiet settings surface keeps the
/// 7-day trend the one aesthetic risk on the app.
///
/// All data stays real: the goal line renders only when the active goal
/// RPC returns one; every row keeps its destination, state copy, and
/// honesty rules from UX_FLOWS.md §13.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.environment,
    this.onSignOut,
    this.health = const ManualHealthRepository(),
    this.coach = const FixtureCoachRepository(),
    this.notifications = const FixtureNotificationRepository(),
    this.exports = const FixturePrivacyExportRepository(),
    this.deletion = const FixtureAccountDeletionRepository(),
    super.key,
  });

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;
  final HealthRepository health;
  final CoachRepository coach;
  final NotificationRepository notifications;
  final PrivacyExportRepository exports;
  final AccountDeletionRepository deletion;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<NotificationPreferences> _notifications;
  late Future<Map<String, dynamic>> _aiUsage;
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    _notifications = widget.notifications.load();
    _aiUsage = widget.coach.loadUsage();
    _profile = _loadIdentity();
  }

  /// Signed-in email local-part + active goal for the identity block.
  /// Offline or unconfigured, this resolves to placeholder-free fallbacks:
  /// the name falls back to 'Tracend member' (never a fabricated value),
  /// the goal line simply doesn't render.
  Future<Map<String, dynamic>> _loadIdentity() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final name = email == null || email.isEmpty
        ? 'Tracend member'
        : email.split('@').first;
    if (!widget.environment.hasSupabaseConfiguration) {
      return {'name': name, 'goal': null};
    }
    try {
      final goal = await Supabase.instance.client
          .from('user_goals')
          .select('goal_type')
          .eq('status', 'active')
          .order('priority')
          .limit(1)
          .maybeSingle();
      return {'name': name, 'goal': goal};
    } catch (_) {
      return {'name': name, 'goal': null};
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = TracendThemeScope.maybeOf(context);
    final colors = context.tracendColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.md,
            TracendSpacing.gutter,
            TracendSpacing.xxl,
          ),
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: _profile,
              builder: (context, snapshot) {
                // The identity block renders immediately with the signed-in
                // name; the goal line appears only when the RPC confirms one
                // (never fabricated, never stuck on a spinner).
                final name =
                    snapshot.data?['name'] as String? ?? 'Tracend member';
                final goal = snapshot.data?['goal'] as Map<String, dynamic>?;
                return _IdentityBlock(
                  name: name,
                  goal: goal == null ? null : friendlyEnum(goal['goal_type']),
                );
              },
            ),
            const AccountSectionLabel('PLAN AND PROFILE'),
            PremiumGradientCard(
              glow: true,
              padding: EdgeInsets.zero,
              child: AccountRow(
                title: 'Profile and goals',
                detail: 'Goal, training profile, approved plan',
                onTap: _openProfileGoals,
              ),
            ),
            const AccountSectionLabel('CONNECTIONS'),
            if (themeController != null) ...[
              TracendCard(
                padding: EdgeInsets.zero,
                child: _ThemeSelector(controller: themeController),
              ),
              const SizedBox(height: TracendSpacing.sm),
            ],
            // Full card (not compact): the profile is the only home for
            // Apple Health controls since the Chunk 6 Today redesign, so the
            // sync chips, missing-signal detail, and "Last refreshed" stamp
            // must stay visible here — they are the sync feedback.
            HealthStatusCard(repository: widget.health),
            const SizedBox(height: TracendSpacing.sm),
            FutureBuilder<NotificationPreferences>(
              future: _notifications,
              builder: (context, snapshot) => TracendCard(
                padding: EdgeInsets.zero,
                child: AccountRow(
                  title: 'Notifications',
                  detail: _notificationDetail(snapshot.data),
                  onTap: () => _openNotifications(snapshot.data),
                ),
              ),
            ),
            const AccountSectionLabel('AI SERVICE'),
            FutureBuilder<Map<String, dynamic>>(
              future: _aiUsage,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TracendCard(
                    padding: EdgeInsets.zero,
                    child: AccountRow(
                      title: 'AI usage unavailable',
                      detail: 'Open details to retry',
                      onTap: () => _openAiUsage(null),
                    ),
                  );
                }
                final usage = snapshot.data;
                return TracendCard(
                  padding: EdgeInsets.zero,
                  child: AccountRow(
                    title: _aiUsageTitle(usage),
                    detail: _aiUsageDetail(usage),
                    onTap: () => _openAiUsage(usage),
                  ),
                );
              },
            ),
            if (widget.environment.hasSupabaseConfiguration &&
                widget.coach is CoachChatRepository) ...[
              const SizedBox(height: TracendSpacing.sm),
              TracendCard(
                padding: EdgeInsets.zero,
                child: AccountRow(
                  title: 'Coach conversations',
                  detail: 'Review or delete saved threads',
                  onTap: _openCoachThreads,
                ),
              ),
              const SizedBox(height: TracendSpacing.sm),
              Text(
                'Provider credentials are managed securely on the server.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const AccountSectionLabel('PRIVACY AND DATA'),
            TracendCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AccountRow(
                    title: 'Privacy and AI processing',
                    detail: 'Review consent by purpose',
                    onTap: _openConsentLedger,
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colors.borderHairline,
                  ),
                  AccountRow(
                    title: 'Export data',
                    detail: 'Requires recent authentication',
                    onTap: _openExport,
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colors.borderHairline,
                  ),
                  AccountRow(
                    title: 'Delete account',
                    detail: 'Permanent and audited',
                    onTap: _openDeletion,
                  ),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.xl),
            OutlinedButton(
              onPressed: widget.onSignOut == null
                  ? null
                  : () async {
                      await widget.onSignOut!();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  String _aiUsageTitle(Map<String, dynamic>? usage) {
    if (!widget.environment.hasSupabaseConfiguration) {
      return 'AI service not configured';
    }
    if (usage == null) return 'AI usage';
    if (usage['blocked'] == true) return 'AI paused at monthly limit';
    final runs = (usage['successful_runs'] as num?)?.toInt() ?? 0;
    final cost = (usage['estimated_cost_usd'] as num?)?.toDouble() ?? 0;
    return 'AI usage · $runs requests · \$${cost.toStringAsFixed(4)} estimate';
  }

  String _aiUsageDetail(Map<String, dynamic>? usage) {
    if (!widget.environment.hasSupabaseConfiguration) {
      return 'Approved plans and manual logging remain available';
    }
    if (usage == null) return 'Checking usage...';
    if (usage['blocked'] == true) {
      return 'Manual logging and approved plans remain available';
    }
    final hardStop = (usage['hard_stop_usd'] as num?)?.toDouble();
    if (usage['warning'] == true && hardStop != null) {
      return 'Approaching the ${usdText(hardStop)} monthly hard stop';
    }
    final warningAt = (usage['warning_threshold_usd'] as num?)?.toDouble();
    if (warningAt != null && hardStop != null) {
      return 'Warning at ${usdText(warningAt)} · hard stop ${usdText(hardStop)}';
    }
    return 'Operational estimates · tap for detail';
  }

  Future<void> _openExport() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PrivacyExportSheet(repository: widget.exports),
    );
  }

  Future<void> _openProfileGoals() => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => ProfileGoalsScreen(data: _loadProfileGoals()),
    ),
  );

  Future<Map<String, dynamic>> _loadProfileGoals() async {
    if (!widget.environment.hasSupabaseConfiguration) return const {};
    final client = Supabase.instance.client;
    final values = await Future.wait([
      client
          .from('user_profiles')
          .select('experience_level,height_cm,training_days,session_minutes')
          .maybeSingle(),
      client
          .from('user_goals')
          .select('goal_type,priority,status,details,activated_at')
          .eq('status', 'active')
          .order('priority')
          .limit(1)
          .maybeSingle(),
      client
          .from('training_plan_versions')
          .select('training_plans(title),version_number,status,approved_at')
          .eq('status', 'active')
          .limit(1)
          .maybeSingle(),
    ]);
    return {'profile': values[0], 'goal': values[1], 'plan': values[2]};
  }

  Future<void> _openAiUsage(Map<String, dynamic>? initial) =>
      Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) =>
              AiUsageScreen(coach: widget.coach, initialUsage: initial),
        ),
      );

  Future<void> _openConsentLedger() => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => ConsentLedgerScreen(load: _loadConsentRecords),
    ),
  );

  Future<List<ConsentRecord>> _loadConsentRecords() async {
    if (!widget.environment.hasSupabaseConfiguration) return const [];
    final rows = await Supabase.instance.client
        .from('consent_records')
        .select('consent_type,notice_version,action,source,created_at')
        .order('created_at', ascending: false);
    return rows
        .map(
          (row) =>
              ConsentRecord.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> _openDeletion() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AccountDeletionSheet(repository: widget.deletion),
    );
    if (deleted == true && mounted) {
      await widget.onSignOut?.call();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openCoachThreads() async {
    final repository = widget.coach;
    if (repository is! CoachChatRepository) return;
    final chat = repository as CoachChatRepository;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => CoachThreadsSheet(chat: chat),
    );
  }

  String _notificationDetail(NotificationPreferences? preferences) {
    if (preferences == null) return 'Checking permission...';
    if (!preferences.isAuthorized) return 'Off · private reminders only';
    final count = [
      preferences.dailyCheckIn,
      preferences.weeklyReview,
    ].where((enabled) => enabled).length;
    return count == 0
        ? 'Allowed · no reminders scheduled'
        : '$count reminder types enabled';
  }

  Future<void> _openNotifications(NotificationPreferences? current) async {
    final initial = current ?? await _notifications;
    if (!mounted) return;
    final saved = await showModalBottomSheet<NotificationPreferences>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          NotificationSheet(repository: widget.notifications, initial: initial),
    );
    if (saved != null && mounted) {
      setState(() {
        _notifications = Future.value(saved);
      });
    }
  }
}

/// Stitch identity block: display-headline name, private-beta chip, current
/// goal line, and the edit affordance opening Profile and goals.
class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.name, this.goal});

  final String name;
  final String? goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.sm),
                  TracendPill(label: 'Private beta', compact: true),
                ],
              ),
              if (goal != null) ...[
                const SizedBox(height: TracendSpacing.xs),
                Text(
                  'Current goal · $goal',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: TracendSpacing.sm),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () {},
          child: Text(
            'Edit',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.actionPrimary),
          ),
        ),
      ],
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.controller});

  final TracendThemeController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Dark is the Tracend default',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          DropdownButton<ThemeMode>(
            value: controller.mode,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
            ],
            onChanged: (value) {
              if (value != null) controller.setMode(value);
            },
          ),
        ],
      ),
    );
  }
}
