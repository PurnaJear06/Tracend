import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';

/// Permanent account deletion, the body of a Tracend sheet: the account
/// password, the exact word `DELETE`, then a destructive confirm before the
/// request leaves the phone (UX_FLOWS.md §13). Pops the outcome once the
/// server confirmed the deletion, or Auth refused the session.
class AccountDeletionSheet extends StatefulWidget {
  const AccountDeletionSheet({required this.repository, super.key});

  final AccountDeletionRepository repository;

  @override
  State<AccountDeletionSheet> createState() => _AccountDeletionSheetState();
}

class _AccountDeletionSheetState extends State<AccountDeletionSheet> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _working = false;

  /// The server has not confirmed the deletion yet; the athlete checks again.
  bool _unconfirmed = false;
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
    setState(() => _error = null);
    final confirmed = await showTracendConfirm(
      context,
      title: 'Delete your account?',
      message:
          'Your plans, logs, health summaries, meals, photos and coaching '
          'data are removed for good. This cannot be undone.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _settle(
      () => widget.repository.delete(
        accountPassword: _password.text,
        confirmation: _confirmation.text,
      ),
    );
  }

  Future<void> _settle(Future<AccountDeletionOutcome> Function() run) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final outcome = await run();
      if (!mounted) return;
      if (outcome == AccountDeletionOutcome.unconfirmed) {
        setState(() => _unconfirmed = true);
      } else {
        Navigator.of(context).pop(outcome);
      }
    } on AuthRetryableFetchException {
      if (mounted) {
        setState(
          () => _error =
              'Deletion did not start. Check the connection and try again.',
        );
      }
    } on AuthException {
      if (mounted) {
        setState(() => _error = 'Your account password was not accepted.');
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      if (mounted) {
        setState(() {
          _unconfirmed = false;
          _error = 'Deletion did not complete. Your account remains available.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final danger = context.tracendColors.stateDanger;
    final error = _error == null
        ? null
        : Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(color: danger),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This permanently removes your sign-in, plans, logs, health summaries, meals, photos, reviews, exports and coaching data. It cannot be undone.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.md),
        if (_unconfirmed) ...[
          Text(
            'Deletion has not been confirmed yet. It may still be finishing on the server.',
            style: textTheme.bodyLarge,
          ),
          if (error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            error,
          ],
          const SizedBox(height: TracendSpacing.lg),
          FilledButton(
            onPressed: _working
                ? null
                : () => _settle(widget.repository.confirm),
            child: Text(_working ? 'Checking…' : 'Check again'),
          ),
        ] else ...[
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Account password'),
          ),
          const SizedBox(height: TracendSpacing.sm),
          TextField(
            controller: _confirmation,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Type DELETE'),
          ),
          if (error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            error,
          ],
          const SizedBox(height: TracendSpacing.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: context.tracendColors.actionOnPrimary,
            ),
            onPressed: _working ? null : _delete,
            child: Text(
              _working ? 'Deleting account…' : 'Permanently delete account',
            ),
          ),
        ],
      ],
    );
  }
}

/// Encrypted export, the body of a Tracend sheet: the account password and a
/// separate export password of 12 or more characters; the download unlocks
/// only when the export is ready (UX_FLOWS.md §13).
class PrivacyExportSheet extends StatefulWidget {
  const PrivacyExportSheet({required this.repository, super.key});

  final PrivacyExportRepository repository;

  @override
  State<PrivacyExportSheet> createState() => _PrivacyExportSheetState();
}

class _PrivacyExportSheetState extends State<PrivacyExportSheet> {
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
    } catch (e) {
      debugPrint('Non-critical error: $e');
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
    } catch (e) {
      debugPrint('Non-critical error: $e');
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final export = _export;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your records as readable JSON and CSV files, plus your private meal and progress photos, in one encrypted file. It expires after seven days or three downloads.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.md),
        if (export != null && export.isReady) ...[
          Text(
            'Ready · ${export.downloadCount} of 3 downloads used',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: TracendSpacing.md),
          FilledButton.icon(
            onPressed: _working ? null : _download,
            icon: const Icon(CupertinoIcons.arrow_down_doc_fill),
            label: const Text('Open secure download'),
          ),
        ] else ...[
          TextField(
            controller: _accountPassword,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
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
                  'At least 12 characters. Keep it safe: Tracend cannot recover it.',
              helperMaxLines: 3,
            ),
            onSubmitted: (_) => _working ? null : _prepare(),
          ),
          const SizedBox(height: TracendSpacing.lg),
          FilledButton(
            onPressed: _working ? null : _prepare,
            child: Text(
              _working
                  ? 'Preparing encrypted export…'
                  : 'Authenticate and prepare',
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(
                color: context.tracendColors.stateDanger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
