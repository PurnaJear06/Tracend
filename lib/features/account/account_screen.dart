import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
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
    final serviceStatus = widget.environment.hasSupabaseConfiguration
        ? 'Client configured'
        : 'Local client not configured';
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
            const TracendCard(
              child: _AccountRow(
                icon: CupertinoIcons.person_fill,
                title: 'Profile and goals',
                detail: 'Lean muscle · Private beta',
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
                child: _AccountRow(
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
                final runs = usage?['successful_runs'] ?? 0;
                final cost = usage?['estimated_cost_usd'] ?? 0;
                final blocked = usage?['blocked'] == true;
                final warning = usage?['warning'] == true;
                return TracendCard(
                  child: _AccountRow(
                    icon: CupertinoIcons.waveform_path,
                    title: blocked
                        ? 'AI paused at monthly limit'
                        : 'AI usage · $runs requests · \$$cost estimate',
                    detail: blocked
                        ? 'Manual logging and approved plans remain available'
                        : warning
                        ? 'Approaching the \$5 monthly hard stop'
                        : '$serviceStatus · \$3 warning · \$5 hard stop',
                  ),
                );
              },
            ),
            if (widget.environment.hasSupabaseConfiguration &&
                widget.coach is CoachChatRepository) ...[
              const SizedBox(height: TracendSpacing.sm),
              TracendCard(
                child: _AccountRow(
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
                  const _AccountRow(
                    icon: CupertinoIcons.lock_fill,
                    title: 'Privacy and AI processing',
                    detail: 'Review consent by purpose',
                  ),
                  Divider(height: TracendSpacing.xl),
                  _AccountRow(
                    icon: CupertinoIcons.arrow_down_doc_fill,
                    title: 'Export data',
                    detail: 'Requires recent authentication',
                    onTap: _openExport,
                  ),
                  Divider(height: TracendSpacing.xl),
                  _AccountRow(
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

  Future<void> _openExport() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PrivacyExportSheet(repository: widget.exports),
    );
  }

  Future<void> _openDeletion() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountDeletionSheet(repository: widget.deletion),
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
    var threads = await chat.loadThreads();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ListView(
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          children: [
            Text(
              'Coach conversations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xs),
            const Text(
              'Messages remain until you delete a thread or delete your account.',
            ),
            const SizedBox(height: TracendSpacing.md),
            if (threads.isEmpty)
              const Text('No saved conversations.')
            else
              for (final thread in threads)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(thread.title),
                  trailing: IconButton(
                    tooltip: 'Delete conversation',
                    icon: const Icon(CupertinoIcons.delete),
                    onPressed: () async {
                      await chat.deleteThread(thread.id);
                      threads = threads
                          .where((item) => item.id != thread.id)
                          .toList();
                      setSheetState(() {});
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _notificationDetail(NotificationPreferences? preferences) {
    if (preferences == null) return 'Checking permission…';
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
      builder: (_) => _NotificationSheet(
        repository: widget.notifications,
        initial: initial,
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _notifications = Future.value(saved);
      });
    }
  }
}

class _AccountDeletionSheet extends StatefulWidget {
  const _AccountDeletionSheet({required this.repository});

  final AccountDeletionRepository repository;

  @override
  State<_AccountDeletionSheet> createState() => _AccountDeletionSheetState();
}

class _AccountDeletionSheetState extends State<_AccountDeletionSheet> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty || _confirmation.text != 'DELETE') {
      setState(() => _error = 'Enter your password and type DELETE exactly.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.repository.delete(
        accountPassword: _password.text,
        confirmation: _confirmation.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException {
      if (mounted) {
        setState(() => _error = 'Your account password was not accepted.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Deletion did not complete. Your account remains available.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.sm,
        TracendSpacing.gutter,
        MediaQuery.viewInsetsOf(context).bottom + TracendSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Permanently delete account',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'This permanently removes your sign-in, plans, logs, health summaries, meals, photos, reviews, exports, and derived coaching data. This cannot be undone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          TextField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Account password'),
          ),
          const SizedBox(height: TracendSpacing.sm),
          TextField(
            controller: _confirmation,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Type DELETE'),
          ),
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
          ],
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.tracendColors.stateDanger,
              ),
              onPressed: _working ? null : _delete,
              child: Text(
                _working ? 'Deleting account…' : 'Permanently delete account',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrivacyExportSheet extends StatefulWidget {
  const _PrivacyExportSheet({required this.repository});

  final PrivacyExportRepository repository;

  @override
  State<_PrivacyExportSheet> createState() => _PrivacyExportSheetState();
}

class _PrivacyExportSheetState extends State<_PrivacyExportSheet> {
  final _accountPassword = TextEditingController();
  final _exportPassword = TextEditingController();
  PrivacyExport? _export;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repository
        .load()
        .then((value) {
          if (mounted) setState(() => _export = value);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _accountPassword.dispose();
    _exportPassword.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_accountPassword.text.isEmpty || _exportPassword.text.length < 12) {
      setState(
        () => _error =
            'Enter your account password and an export password of 12 or more characters.',
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final value = await widget.repository.request(
        accountPassword: _accountPassword.text,
        exportPassword: _exportPassword.text,
      );
      _accountPassword.clear();
      _exportPassword.clear();
      if (mounted) setState(() => _export = value);
    } on AuthException {
      if (mounted) {
        setState(() => _error = 'Your account password was not accepted.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'The encrypted export could not be prepared. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download() async {
    final value = _export;
    if (value == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.repository.download(value.id);
      if (mounted) {
        setState(
          () => _export = PrivacyExport(
            id: value.id,
            status: value.status,
            byteSize: value.byteSize,
            expiresAt: value.expiresAt,
            downloadCount: value.downloadCount + 1,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The secure download could not be opened. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.sm,
        TracendSpacing.gutter,
        MediaQuery.viewInsetsOf(context).bottom + TracendSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Encrypted account export',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Includes your readable JSON and CSV records plus private meal and progress media. The file expires after seven days or three downloads.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_export?.isReady ?? false) ...[
            const SizedBox(height: TracendSpacing.md),
            Text('Ready · ${_export!.downloadCount} of 3 downloads used'),
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _working ? null : _download,
                icon: const Icon(CupertinoIcons.arrow_down_doc_fill),
                label: const Text('Open secure download'),
              ),
            ),
          ] else ...[
            const SizedBox(height: TracendSpacing.md),
            TextField(
              controller: _accountPassword,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Account password'),
            ),
            const SizedBox(height: TracendSpacing.sm),
            TextField(
              controller: _exportPassword,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'New export password',
                helperText:
                    'At least 12 characters. Store it safely; Tracend cannot recover it.',
              ),
              onSubmitted: (_) => _working ? null : _prepare(),
            ),
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _working ? null : _prepare,
                child: Text(
                  _working
                      ? 'Preparing encrypted export…'
                      : 'Authenticate and prepare',
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.controller});
  final TracendThemeController controller;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        CupertinoIcons.circle_lefthalf_fill,
        color: context.tracendColors.actionPrimary,
      ),
      const SizedBox(width: TracendSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(icon, color: context.tracendColors.actionPrimary),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(detail, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(CupertinoIcons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet({required this.repository, required this.initial});

  final NotificationRepository repository;
  final NotificationPreferences initial;

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  late bool _daily = widget.initial.dailyCheckIn;
  late bool _weekly = widget.initial.weeklyReview;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.configure(
        dailyCheckIn: _daily,
        weeklyReview: _weekly,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on PlatformException catch (error) {
      setState(() {
        _saving = false;
        _error = error.code == 'permission_denied'
            ? 'Notifications are disabled in iOS Settings.'
            : 'Notifications could not be updated. Try again.';
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Notifications could not be updated. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.sm,
        TracendSpacing.gutter,
        MediaQuery.viewInsetsOf(context).bottom + TracendSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private reminders',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Lock-screen text stays generic. It never includes health, nutrition, workout, or photo details.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Daily check-in reminder'),
            subtitle: const Text('Every day at 7:00 PM'),
            value: _daily,
            onChanged: _saving
                ? null
                : (value) => setState(() => _daily = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Weekly review reminder'),
            subtitle: const Text('Sunday at 6:00 PM'),
            value: _weekly,
            onChanged: _saving
                ? null
                : (value) => setState(() => _weekly = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            Text(
              _error!,
              style: TextStyle(color: context.tracendColors.stateDanger),
            ),
          ],
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save reminders'),
            ),
          ),
        ],
      ),
    ),
  );
}
