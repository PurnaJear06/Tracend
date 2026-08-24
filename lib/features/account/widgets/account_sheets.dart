import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';

/// Permanent account deletion sheet: password + exact `DELETE` confirmation
/// (UX_FLOWS.md §13). Returns true only after the server completes.
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
    } catch (e) {
      debugPrint('Non-critical error: $e');
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
                _working ? 'Deleting account...' : 'Permanently delete account',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Encrypted export sheet: account password + separate 12-character export
/// password; download unlocks only when the export is ready (UX_FLOWS.md §13).
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
                      ? 'Preparing encrypted export...'
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
