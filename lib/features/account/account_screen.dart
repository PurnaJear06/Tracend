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

  @override
  void initState() {
    super.initState();
    _notifications = widget.notifications.load();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = TracendThemeScope.maybeOf(context);
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
            PremiumGradientCard(
              glow: true,
              child: AccountRow(
                icon: CupertinoIcons.person_fill,
                title: 'Profile and goals',
                detail: 'Goal, training profile, approved plan',
                onTap: _openProfileGoals,
              ),
            ),
            const SectionLabel('Connections'),
            if (themeController != null) ...[
              TracendCard(child: _ThemeSelector(controller: themeController)),
              const SizedBox(height: TracendSpacing.sm),
            ],
            HealthStatusCard(repository: widget.health, compact: true),
            const SizedBox(height: TracendSpacing.sm),
            FutureBuilder<NotificationPreferences>(
              future: _notifications,
              builder: (context, snapshot) => TracendCard(
                child: AccountRow(
                  icon: CupertinoIcons.bell_fill,
                  title: 'Notifications',
                  detail: _notificationDetail(snapshot.data),
                  onTap: () => _openNotifications(snapshot.data),
                ),
              ),
            ),
            const SectionLabel('AI service'),
            FutureBuilder<Map<String, dynamic>>(
              future: widget.coach.loadUsage(),
              builder: (context, snapshot) {
                final usage = snapshot.data;
                return TracendCard(
                  child: AccountRow(
                    icon: CupertinoIcons.waveform_path,
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
                child: AccountRow(
                  icon: CupertinoIcons.bubble_left_bubble_right_fill,
                  title: 'Coach conversations',
                  detail: 'Review or delete saved threads',
                  onTap: _openCoachThreads,
                ),
              ),
            ],
            const SectionLabel('Privacy and data'),
            TracendCard(
              child: Column(
                children: [
                  AccountRow(
                    icon: CupertinoIcons.lock_fill,
                    title: 'Privacy and AI processing',
                    detail: 'Review consent by purpose',
                    onTap: _openConsentLedger,
                  ),
                  Divider(height: TracendSpacing.xl),
                  AccountRow(
                    icon: CupertinoIcons.arrow_down_doc_fill,
                    title: 'Export data',
                    detail: 'Requires recent authentication',
                    onTap: _openExport,
                  ),
                  Divider(height: TracendSpacing.xl),
                  AccountRow(
                    icon: CupertinoIcons.delete_solid,
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
      return 'Approaching the \$${hardStop.toStringAsFixed(0)} monthly hard stop';
    }
    final warningAt = (usage['warning_threshold_usd'] as num?)?.toDouble();
    if (warningAt != null && hardStop != null) {
      return 'Warning at \$${warningAt.toStringAsFixed(0)} · hard stop \$${hardStop.toStringAsFixed(0)}';
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

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.controller});

  final TracendThemeController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.actionPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(TracendRadii.control),
          ),
          child: Icon(
            CupertinoIcons.circle_lefthalf_fill,
            size: 18,
            color: colors.actionPrimary,
          ),
        ),
        const SizedBox(width: TracendSpacing.sm),
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
    );
  }
}
