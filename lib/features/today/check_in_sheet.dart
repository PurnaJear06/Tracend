import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';

Future<void> showCheckInSheet(
  BuildContext context,
  AppEnvironment environment,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _CheckInSheet(environment: environment),
);

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({required this.environment});
  final AppEnvironment environment;
  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  final _values = <String, int>{
    'sleep_quality': 3,
    'energy': 3,
    'soreness': 3,
    'hunger': 3,
    'mood': 3,
    'pain_severity': 0,
  };
  final _note = TextEditingController();
  bool _available = true;
  bool _saving = false;
  static const _key = 'daily_check_in_pending';
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      ..._values,
      'available_to_train': _available,
      'note': _note.text.trim(),
    };
    final envelope = {
      'idempotency_key': newIdempotencyKey(),
      'payload': payload,
    };
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(envelope));
    try {
      if (widget.environment.hasSupabaseConfiguration) {
        await Supabase.instance.client.rpc(
          'save_daily_check_in',
          params: {
            'local_date': DateTime.now().toIso8601String().substring(0, 10),
            'timezone': DateTime.now().timeZoneName,
            'idempotency_key': envelope['idempotency_key'],
            'payload': payload,
          },
        );
      }
      await preferences.remove(_key);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Check-in saved')));
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check-in saved on this device. It will need a connection to sync.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      TracendSpacing.gutter,
      TracendSpacing.md,
      TracendSpacing.gutter,
      MediaQuery.viewInsetsOf(context).bottom + TracendSpacing.lg,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        Text(
          'Daily check-in',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Use what you know now. Missing HealthKit data does not block training.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        for (final entry in _values.entries)
          _RatingRow(
            label: _label(entry.key),
            value: entry.value,
            onChanged: (v) => setState(() => _values[entry.key] = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Available to train today'),
          value: _available,
          onChanged: (v) => setState(() => _available = v),
        ),
        TextField(
          controller: _note,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save check-in'),
        ),
      ],
    ),
  );
  String _label(String key) => switch (key) {
    'sleep_quality' => 'Sleep quality',
    'energy' => 'Energy',
    'soreness' => 'Soreness',
    'hunger' => 'Hunger',
    'mood' => 'Mood',
    'pain_severity' => 'Pain',
    _ => key,
  };
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final max = label == 'Pain' ? 10 : 5;
    return Semantics(
      label: '$label: $value of $max',
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
            tooltip: 'Decrease $label',
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
            tooltip: 'Increase $label',
          ),
        ],
      ),
    );
  }
}
