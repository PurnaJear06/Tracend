import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Today while the app is open on the saved plan: the brief, check-in, meals
/// and Coach's call all come from the server, so Today says so and points to
/// Train, where the saved plan and the workout work.
class OfflineToday extends StatelessWidget {
  const OfflineToday({
    required this.onOpenTrain,
    required this.onOpenAccount,
    required this.onRetry,
    super.key,
  });

  final VoidCallback onOpenTrain;
  final VoidCallback onOpenAccount;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => _OfflineView(
    title: 'Today',
    heading: 'You are offline.',
    message:
        'Your saved plan and your workout are in Train. Today’s brief, '
        'check-in, meals and Coach come back with a connection.',
    onOpenTrain: onOpenTrain,
    onRetry: onRetry,
    trailing: AccountButton(onPressed: onOpenAccount),
  );
}

/// A tab that needs the server (Coach, Meals, Progress) while the app is open
/// on the saved plan. [needs] names what the tab does, for example "Coach".
class OfflineTab extends StatelessWidget {
  const OfflineTab({
    required this.title,
    required this.needs,
    required this.onOpenTrain,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String needs;
  final VoidCallback onOpenTrain;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => _OfflineView(
    title: title,
    heading: '$needs needs a connection.',
    message:
        'You are offline. Your saved plan and your workout still work in '
        'Train.',
    onOpenTrain: onOpenTrain,
    onRetry: onRetry,
  );
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({
    required this.title,
    required this.heading,
    required this.message,
    required this.onOpenTrain,
    required this.onRetry,
    this.trailing,
  });

  final String title;
  final String heading;
  final String message;
  final VoidCallback onOpenTrain;
  final Future<void> Function() onRetry;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: TracendScrollView(
        title: title,
        trailing: trailing,
        onRefresh: onRetry,
        children: [
          const StatusChip(
            label: 'Offline',
            icon: CupertinoIcons.wifi_slash,
            tone: StatusTone.caution,
          ),
          const SizedBox(height: TracendSpacing.sm),
          TracendCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(heading, style: textTheme.headlineSmall),
                const SizedBox(height: TracendSpacing.xs),
                Text(message),
                const SizedBox(height: TracendSpacing.md),
                FilledButton(
                  onPressed: onOpenTrain,
                  child: const Text('Open Train'),
                ),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
