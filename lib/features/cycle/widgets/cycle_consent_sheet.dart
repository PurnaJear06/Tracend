import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// What the consent sheet says. The same words are on the privacy page.
const cycleConsentBody =
    'Tracend stores your cycle answers and the period days you log or allow '
    'from Apple Health, to read your recovery, weight and energy fairly. It is '
    'never used for ads or shared. Coach uses it only after you accept an AI '
    'notice that names it. You can delete it any time in Account.';

/// Asks for her agreement to keep cycle data and records it. Completes true
/// once the agreement is stored, false when she says "Not now" or leaves, and
/// true when [repository] already holds one.
Future<bool> ensureCycleConsent(
  BuildContext context,
  CycleRepository repository,
) async {
  if (await _alreadyGranted(repository)) return true;
  if (!context.mounted) return false;
  final agreed = await showTracendSheet<bool>(
    context,
    title: 'Cycle data',
    scrollable: false,
    padding: EdgeInsets.zero,
    builder: (_) => _CycleConsentSheet(repository: repository),
  );
  return agreed ?? false;
}

Future<bool> _alreadyGranted(CycleRepository repository) async {
  try {
    return await repository.consentGranted();
  } catch (error) {
    // Unknown: ask, which records a fresh grant.
    logNonCritical(error, 'cycle consent not read');
    return false;
  }
}

class _CycleConsentSheet extends StatefulWidget {
  const _CycleConsentSheet({required this.repository});

  final CycleRepository repository;

  @override
  State<_CycleConsentSheet> createState() => _CycleConsentSheetState();
}

class _CycleConsentSheetState extends State<_CycleConsentSheet> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _agree() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.repository.grantConsent();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      logNonCritical(error, 'cycle consent not saved');
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.xs,
        TracendSpacing.gutter,
        TracendSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(cycleConsentBody, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: TracendSpacing.lg),
          if (_failed) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                'Your choice was not saved. Check the connection and try '
                'again.',
                style: TextStyle(color: colors.stateDanger),
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          FilledButton(
            onPressed: _saving ? null : _agree,
            child: Text(_saving ? 'Saving…' : 'Agree'),
          ),
          const SizedBox(height: TracendSpacing.xs),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
