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
import 'package:tracend/features/account/widgets/consent_history_screen.dart';
import 'package:tracend/features/account/widgets/notification_settings.dart';
import 'package:tracend/features/account/widgets/profile_goals_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Account: one iOS inset-grouped settings page (UX_FLOWS.md §13).
///
/// The identity block comes first (name from the email local-part, the
/// private-beta pill, the current goal when the active-goal query returns
/// one). Then grouped lists under sentence-case section labels: Plan, Health,
/// Appearance, Notifications, AI coach and Privacy, with sign-out at the foot.
/// Every value is real; rows without a destination show no chevron.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.environment,
    this.onSignOut,
    this.health = const ManualHealthRepository(),
    this.coach = const FixtureCoachRepository(),
    this.notifications = const FixtureNotificationRepository(),
    this.exports = const FixturePrivacyExportRepository(),
    this.deletion = const FixtureAccountDeletionRepository(),
    this.aiConsent,
    super.key,
  });

  final AppEnvironment environment;
  final Future<void> Function()? onSignOut;
  final HealthRepository health;
  final CoachRepository coach;
  final NotificationRepository notifications;
  final PrivacyExportRepository exports;
  final AccountDeletionRepository deletion;

  /// Where AI coaching is turned on or off. Null without a backend.
  final AiCoachingConsentController? aiConsent;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<Map<String, dynamic>> _aiUsage;
  late Future<Map<String, dynamic>> _profile;
  late Future<HealthSyncStatus> _health;

  @override
  void initState() {
    super.initState();
    _aiUsage = widget.coach.loadUsage();
    _profile = _loadIdentity();
    _health = widget.health.loadStatus();
  }

  /// Signed-in email local-part and active goal for the identity block.
  /// Offline or unconfigured, the name falls back to 'Tracend member' (never
  /// a fabricated value) and the goal line does not render.
  Future<Map<String, dynamic>> _loadIdentity() async {
    final email = widget.environment.hasSupabaseConfiguration
        ? Supabase.instance.client.auth.currentUser?.email
        : null;
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
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    final configured = widget.environment.hasSupabaseConfiguration;
    final aiConsent = widget.aiConsent;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            TracendSpacing.xs,
            gutter,
            TracendSpacing.xxl,
          ),
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: _profile,
              builder: (context, snapshot) {
                // The identity renders at once with the fallback name; the
                // goal line appears only when the query confirms one.
                final name =
                    snapshot.data?['name'] as String? ?? 'Tracend member';
                final goal = snapshot.data?['goal'] as Map<String, dynamic>?;
                return _IdentityBlock(
                  name: name,
                  goal: goal == null ? null : friendlyEnum(goal['goal_type']),
                );
              },
            ),
            const SectionLabel('Plan'),
            TracendGroupedList(
              children: [
                TracendListRow(
                  title: 'Profile and goals',
                  subtitle: 'Goal, training profile and approved plan',
                  leading: const TracendRowIcon(icon: CupertinoIcons.person),
                  onTap: _openProfileGoals,
                ),
              ],
            ),
            const SectionLabel('Health'),
            FutureBuilder<HealthSyncStatus>(
              future: _health,
              builder: (context, snapshot) => TracendGroupedList(
                children: [
                  TracendListRow(
                    title: 'Apple Health',
                    subtitle: snapshot.hasData
                        ? appleHealthStatusText(snapshot.data!)
                        : snapshot.hasError
                        ? 'Status could not be read'
                        : 'Checking…',
                    leading: const TracendRowIcon(icon: CupertinoIcons.heart),
                    onTap: _openHealth,
                  ),
                ],
              ),
            ),
            if (themeController != null) ...[
              const SectionLabel('Appearance'),
              _AppearanceControl(controller: themeController),
            ],
            const SectionLabel('Notifications'),
            NotificationSettings(repository: widget.notifications),
            const SectionLabel('AI coach'),
            ListenableBuilder(
              listenable: Listenable.merge([?aiConsent]),
              builder: (context, _) => FutureBuilder<Map<String, dynamic>>(
                future: _aiUsage,
                builder: (context, snapshot) => TracendGroupedList(
                  children: [
                    if (aiConsent != null)
                      TracendListRow(
                        title: 'AI coaching',
                        subtitle: aiConsent.granted
                            ? 'On · ${aiConsent.notice.providerLabel} writes Coach answers'
                            : 'Off · plans and logging still work',
                        leading: const TracendRowIcon(
                          icon: CupertinoIcons.chat_bubble_text,
                        ),
                        onTap: () =>
                            showAiCoachingConsentSheet(context, aiConsent),
                      ),
                    _usageRow(context, snapshot),
                    if (configured && widget.coach is CoachChatRepository)
                      TracendListRow(
                        title: 'Coach conversations',
                        subtitle: 'Review or delete saved conversations',
                        leading: const TracendRowIcon(
                          icon: CupertinoIcons.text_bubble,
                        ),
                        onTap: _openCoachThreads,
                      ),
                  ],
                ),
              ),
            ),
            const AccountFootnote(
              'Provider keys stay on Tracend’s server, never on this phone.',
            ),
            const SectionLabel('Privacy'),
            TracendGroupedList(
              children: [
                TracendListRow(
                  title: 'Export data',
                  subtitle: 'An encrypted copy of everything you logged',
                  leading: const TracendRowIcon(
                    icon: CupertinoIcons.arrow_down_doc,
                  ),
                  onTap: _openExport,
                ),
                TracendListRow(
                  title: 'Consent history',
                  subtitle: 'Your privacy and AI choices, with dates',
                  leading: const TracendRowIcon(icon: CupertinoIcons.lock),
                  onTap: _openConsentHistory,
                ),
                TracendListRow(
                  title: 'Delete account',
                  subtitle: 'Permanent; asks for your password',
                  leading: TracendRowIcon(
                    icon: CupertinoIcons.delete,
                    color: context.tracendColors.stateDanger,
                  ),
                  onTap: _openDeletion,
                ),
              ],
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

  TracendListRow _usageRow(
    BuildContext context,
    AsyncSnapshot<Map<String, dynamic>> snapshot,
  ) {
    const icon = TracendRowIcon(icon: CupertinoIcons.chart_bar);
    if (!widget.environment.hasSupabaseConfiguration) {
      return TracendListRow(
        title: 'AI service not configured',
        subtitle: 'Approved plans and manual logging remain available',
        leading: icon,
        onTap: () => _openAiUsage(null),
      );
    }
    if (snapshot.hasError) {
      return TracendListRow(
        title: 'AI usage unavailable',
        subtitle: 'Open to try again',
        leading: icon,
        onTap: () => _openAiUsage(null),
      );
    }
    final data = snapshot.data;
    if (data == null) {
      return const TracendListRow(
        title: 'AI usage this month',
        subtitle: 'Checking usage…',
        leading: icon,
      );
    }
    final usage = AiUsageSummary.fromJson(data);
    return TracendListRow(
      title: 'AI usage this month',
      subtitle: usage.accountLine,
      leading: icon,
      onTap: () => _openAiUsage(data),
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
          .select(
            'experience_level,height_cm,training_days,session_minutes,sex,'
            'birth_year,daily_activity,equipment,equipment_note,avoid_patterns,'
            'limitations_note,nutrition_note',
          )
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

  Future<void> _openHealth() async {
    await showTracendSheet<void>(
      context,
      title: 'Apple Health',
      subtitle: 'Read-only summaries for your plan and the Coach',
      builder: (_) =>
          HealthStatusCard(repository: widget.health, onSynced: _reloadHealth),
    );
    _reloadHealth();
  }

  void _reloadHealth() {
    if (!mounted) return;
    setState(() => _health = widget.health.loadStatus());
  }

  Future<void> _openAiUsage(Map<String, dynamic>? initial) =>
      Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) =>
              AiUsageScreen(coach: widget.coach, initialUsage: initial),
        ),
      );

  Future<void> _openConsentHistory() => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => ConsentHistoryScreen(load: _loadConsentRecords),
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

  Future<void> _openExport() => showTracendSheet<void>(
    context,
    title: 'Export your data',
    builder: (_) => PrivacyExportSheet(repository: widget.exports),
  );

  Future<void> _openDeletion() async {
    final outcome = await showTracendSheet<AccountDeletionOutcome>(
      context,
      title: 'Delete account',
      builder: (_) => AccountDeletionSheet(repository: widget.deletion),
    );
    if (outcome == null || !mounted) return;
    // The toast sits in the root overlay, so it outlives this page.
    TracendToast.show(
      context,
      outcome == AccountDeletionOutcome.deleted
          ? 'Your account was deleted'
          : 'Signed out. Sign in to see whether the account remains.',
      icon: outcome == AccountDeletionOutcome.deleted
          ? CupertinoIcons.checkmark_alt
          : CupertinoIcons.info,
    );
    await widget.onSignOut?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openCoachThreads() async {
    final repository = widget.coach;
    if (repository is! CoachChatRepository) return;
    await showTracendSheet<void>(
      context,
      title: 'Coach conversations',
      builder: (_) =>
          CoachThreadsSheet(chat: repository as CoachChatRepository),
    );
  }
}

/// Apple Health status in plain words: "Updated today at 14:05".
String appleHealthStatusText(HealthSyncStatus status, {DateTime? now}) {
  final synced = status.lastSuccessfulSync;
  if (status.state == HealthConnectionState.unavailable) {
    return 'Not available on this iPhone';
  }
  if (synced == null) return 'Not connected · manual logging works';
  final local = synced.toLocal();
  final day = friendlyDate(local, now: now);
  final updated =
      'Updated ${day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : day} '
      'at ${clockTime(local)}';
  return switch (status.state) {
    HealthConnectionState.stale => '$updated · needs a refresh',
    HealthConnectionState.partial => '$updated · some signals missing',
    _ => updated,
  };
}

/// The identity block: the name, the private-beta pill and the current goal.
/// Editing lives in Profile and goals, so there is no separate edit control.
class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.name, this.goal});

  final String name;
  final String? goal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.xs, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Wrap(
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusChip(
                label: 'Private beta',
                icon: CupertinoIcons.lock_shield,
              ),
              if (goal != null)
                Text('Current goal: $goal', style: textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

/// System / Dark / Light, applied at once.
class _AppearanceControl extends StatelessWidget {
  const _AppearanceControl({required this.controller});

  final TracendThemeController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: 'Appearance',
        container: true,
        child: TracendSegmentedControl<ThemeMode>(
          segments: const [
            (ThemeMode.system, 'System'),
            (ThemeMode.dark, 'Dark'),
            (ThemeMode.light, 'Light'),
          ],
          selected: controller.mode,
          onChanged: controller.setMode,
        ),
      ),
      const AccountFootnote(
        'System follows your iPhone’s setting. Dark is the Tracend default.',
      ),
    ],
  );
}
