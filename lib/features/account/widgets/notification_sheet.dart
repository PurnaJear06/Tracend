import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/notification_repository.dart';

/// Private reminder preferences sheet (UX_FLOWS.md §13). Lock-screen copy
/// stays generic; permission is requested on save when enabled.
class NotificationSheet extends StatefulWidget {
  const NotificationSheet({
    required this.repository,
    required this.initial,
    super.key,
  });

  final NotificationRepository repository;
  final NotificationPreferences initial;

  @override
  State<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<NotificationSheet> {
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
    } catch (e) {
      debugPrint('Non-critical error: $e');
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
              child: Text(_saving ? 'Saving...' : 'Save reminders'),
            ),
          ),
        ],
      ),
    ),
  );
}
