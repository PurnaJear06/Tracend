import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// The lock-screen text of the rest alert. The native side sends exactly this
/// (`ios/Runner/SceneDelegate.swift`); the disclosure shows it before iOS
/// asks for permission.
const restAlertLockScreenText = 'Rest timer finished';

/// Account › Notifications as switch rows (UX_FLOWS.md §13): the daily
/// check-in and weekly review reminders, and rest timer alerts. Each switch
/// applies at once. Turning rest alerts on before iOS has been asked shows
/// the lock-screen text first; off or denied keeps the timer in the app.
class NotificationSettings extends StatefulWidget {
  const NotificationSettings({required this.repository, super.key});

  final NotificationRepository repository;

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  NotificationPreferences? _preferences;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await widget.repository.load();
      if (mounted) setState(() => _preferences = preferences);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() => _message = 'Notification settings could not be read.');
      }
    }
  }

  Future<void> _setRestAlerts(bool on) async {
    final current = _preferences;
    if (current == null) return;
    if (on && current.authorizationStatus == 'not_determined') {
      final proceed = await showTracendConfirm(
        context,
        title: 'Turn on rest timer alerts?',
        message:
            'When a rest ends while your phone is locked, the lock screen '
            'shows “$restAlertLockScreenText” and nothing else. iOS asks to '
            'allow notifications next. Without them, the timer stays in the '
            'app.',
        confirmLabel: 'Continue',
        cancelLabel: 'Not now',
      );
      if (!proceed || !mounted) return;
    }
    await _apply(rest: on);
  }

  Future<void> _apply({bool? daily, bool? weekly, bool? rest}) async {
    final current = _preferences;
    if (current == null || _saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final saved = await widget.repository.configure(
        dailyCheckIn: daily ?? current.dailyCheckIn,
        weeklyReview: weekly ?? current.weeklyReview,
        restTimerAlertsEnabled: rest ?? current.restTimerAlertsEnabled,
      );
      unawaited(TracendHaptics.light());
      if (mounted) setState(() => _preferences = saved);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error.code == 'permission_denied'
            ? rest == true
                  ? 'Notifications are off for Tracend in iOS Settings, so the rest timer stays in the app.'
                  : 'Notifications are off for Tracend in iOS Settings. Turn them on there to get reminders.'
            : 'Notifications could not be updated. Try again.',
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(
          () => _message = 'Notifications could not be updated. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    final enabled = preferences != null && !_saving;
    final denied = preferences?.authorizationStatus == 'denied';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TracendGroupedList(
          children: [
            _SwitchRow(
              title: 'Daily check-in reminder',
              subtitle: 'Every day at 7:00 PM',
              value: preferences?.dailyCheckIn ?? false,
              onChanged: enabled ? (on) => _apply(daily: on) : null,
            ),
            _SwitchRow(
              title: 'Weekly review reminder',
              subtitle: 'Sunday at 6:00 PM',
              value: preferences?.weeklyReview ?? false,
              onChanged: enabled ? (on) => _apply(weekly: on) : null,
            ),
            _SwitchRow(
              title: 'Rest timer alerts',
              subtitle:
                  'When a rest ends with the phone locked. The lock screen '
                  'shows “$restAlertLockScreenText”.',
              value: preferences?.restTimerAlertsEnabled ?? false,
              onChanged: enabled ? _setRestAlerts : null,
            ),
          ],
        ),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: AccountFootnote(
              _message!,
              color: context.tracendColors.stateDanger,
            ),
          )
        else if (denied)
          const AccountFootnote(
            'Notifications are off for Tracend in iOS Settings. Reminders '
            'and rest alerts stay off until you allow them there.',
          ),
        const AccountFootnote(
          'Lock-screen text stays generic. It never includes health, '
          'nutrition, workout or photo details.',
        ),
      ],
    );
  }
}

/// A grouped-list row with a trailing switch. VoiceOver reads the title,
/// detail and switch state as one element.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: TracendListRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    ),
  );
}
