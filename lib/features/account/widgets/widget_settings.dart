import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Account › Widgets: whether the Lock Screen shows health numbers: in the
/// widgets, and the kg and reps of the set in the workout's Live Activity
/// (UX_FLOWS.md §13, SECURITY_PRIVACY.md §10). Off until chosen. Turning it
/// off removes the numbers from what they show at once.
class WidgetSettings extends StatefulWidget {
  const WidgetSettings({required this.publisher, super.key});

  final TodayWidgetPublisher publisher;

  @override
  State<WidgetSettings> createState() => _WidgetSettingsState();
}

class _WidgetSettingsState extends State<WidgetSettings> {
  bool? _shown;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final shown = await widget.publisher.lockScreenNumbers();
    if (mounted) setState(() => _shown = shown);
  }

  Future<void> _set(bool shown) async {
    setState(() => _shown = shown);
    unawaited(TracendHaptics.light());
    final applied = await widget.publisher.setLockScreenNumbers(shown);
    if (applied || !mounted) return;
    // The switch is off for good, but the numbers already on the Lock Screen
    // could not be removed yet; Tracend retries until they are gone.
    TracendToast.show(
      context,
      'Numbers are off. Tracend could not remove the old ones from the Lock '
      'Screen yet and is retrying.',
      icon: CupertinoIcons.exclamationmark_triangle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TracendGroupedList(
          children: [
            MergeSemantics(
              child: TracendListRow(
                title: 'Health numbers on the Lock Screen',
                subtitle: shown
                    ? 'On · recovery, today’s session, protein and your '
                          'current set’s kg and reps show while the phone is '
                          'locked'
                    : 'Off · Lock Screen widgets show Tracend and nothing '
                          'else; the workout card shows no kg or reps',
                trailing: Switch.adaptive(
                  value: shown,
                  onChanged: _shown == null ? null : _set,
                ),
              ),
            ),
          ],
        ),
        const AccountFootnote(
          'Anyone holding your locked phone can read Lock Screen widgets and '
          'the workout card. Home Screen widgets show your day once the phone '
          'is unlocked.',
        ),
      ],
    );
  }
}
