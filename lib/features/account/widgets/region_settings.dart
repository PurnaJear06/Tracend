import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/region_repository.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// What the sheet returns: the chosen code, or null for "Not set". A sheet
/// that is dismissed returns no pick at all.
class _CountryPick {
  const _CountryPick(this.code);
  final String? code;
}

/// Account › Region: the athlete's optional country (UX_FLOWS.md §13). It
/// only chooses which national guidelines Coach may cite; with none chosen the
/// app behaves as it always did, and no plan number changes either way.
class RegionSettings extends StatefulWidget {
  const RegionSettings({required this.repository, super.key});

  final RegionRepository repository;

  @override
  State<RegionSettings> createState() => _RegionSettingsState();
}

class _RegionSettingsState extends State<RegionSettings> {
  bool _loaded = false;
  bool _unreadable = false;
  bool _saving = false;
  String? _code;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final code = await widget.repository.load();
      if (mounted) {
        setState(() {
          _code = code;
          _loaded = true;
        });
      }
    } catch (error) {
      debugPrint('Non-critical error: country not read: $error');
      if (mounted) setState(() => _unreadable = true);
    }
  }

  String get _subtitle {
    if (_unreadable) return 'Could not be read · open to try again';
    if (!_loaded) return 'Checking…';
    final label = countryLabel(_code);
    if (label == null) {
      return 'Not set · Coach uses guidance that applies everywhere';
    }
    return hasRegionalModule(_code)
        ? '$label · Coach can cite $label’s national guidelines'
        : '$label · Coach uses guidance that applies everywhere';
  }

  Future<void> _choose() async {
    if (_saving) return;
    if (_unreadable) {
      setState(() => _unreadable = false);
      await _load();
      return;
    }
    if (!_loaded) return;
    final pick = await showTracendSheet<_CountryPick>(
      context,
      title: 'Country',
      subtitle: 'Optional. Chooses which national guidelines Coach can cite.',
      builder: (sheetContext) => _CountryChoices(selected: _code),
    );
    if (pick == null || pick.code == _code || !mounted) return;
    unawaited(TracendHaptics.light());
    setState(() => _saving = true);
    try {
      final stored = await widget.repository.save(pick.code);
      if (mounted) setState(() => _code = stored);
    } catch (error) {
      debugPrint('Non-critical error: country not saved: $error');
      if (mounted) {
        TracendToast.show(
          context,
          'Your country was not saved. Check your connection and try again.',
          icon: CupertinoIcons.exclamationmark_triangle,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TracendGroupedList(
        children: [
          TracendListRow(
            title: 'Country',
            subtitle: _subtitle,
            leading: const TracendRowIcon(icon: CupertinoIcons.globe),
            onTap: _loaded || _unreadable ? _choose : null,
          ),
        ],
      ),
      const AccountFootnote(
        'Optional. Coach uses it only to pick which national food and '
        'body-size guidelines it can cite. Your plan’s numbers do not change.',
      ),
    ],
  );
}

class _CountryChoices extends StatelessWidget {
  const _CountryChoices({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final choices = <(String?, String)>[
      for (final entry in regionalModuleCountries.entries)
        (entry.key, entry.value),
      (otherCountryCode, 'Another country'),
      (null, 'Not set'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.md),
      child: TracendGroupedList(
        children: [
          for (final (code, label) in choices)
            Semantics(
              selected: code == selected,
              child: TracendListRow(
                title: label,
                subtitle: switch (code) {
                  null => 'Coach uses guidance that applies everywhere',
                  otherCountryCode => 'No national guidance to add yet',
                  _ => null,
                },
                trailing: code == selected
                    ? const Icon(CupertinoIcons.checkmark_alt)
                    : null,
                onTap: () => Navigator.of(context).pop(_CountryPick(code)),
              ),
            ),
        ],
      ),
    );
  }
}
