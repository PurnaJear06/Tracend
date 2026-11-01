import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/widgets/account_sheets.dart';
import 'package:tracend/features/onboarding/choice_widgets.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// The legal pages the app asks the athlete to agree to, hosted on the
/// website. A page's version is its "Last updated" date (ISO), so editing a
/// page means a new date here too (`test/legal_versions_test.dart` fails until
/// they match), and athletes whose newest grant is older are asked again at
/// launch. Git history keeps every earlier version of each page.
abstract final class LegalNotices {
  /// `site/src/pages/beta-terms.astro`.
  static const termsVersion = '2026-11-02';

  /// `site/src/pages/privacy.astro`; health-data consent is given against it.
  static const privacyVersion = '2026-11-02';

  static final termsUrl = Uri.parse('https://tracend.pages.dev/beta-terms/');
  static final privacyUrl = Uri.parse('https://tracend.pages.dev/privacy/');
}

/// One agreement the app records in `consent_records`, with the version of
/// the page it was given against.
enum LegalConsent {
  terms('terms', LegalNotices.termsVersion),
  privacy('privacy', LegalNotices.privacyVersion),
  healthData('health_data', LegalNotices.privacyVersion);

  const LegalConsent(this.type, this.version);

  /// The `consent_type` stored.
  final String type;

  /// The page version this build shows.
  final String version;
}

/// The agreements whose newest record is missing, withdrawn, or a grant of an
/// older version than this build shows. [rows] are newest first. A grant of a
/// newer version (recorded by a later build) still counts.
Set<LegalConsent> outdatedLegalConsents(List<Map<String, dynamic>> rows) => {
  for (final consent in LegalConsent.values)
    if (!_grantedCurrent(
      rows.where((row) => row['consent_type'] == consent.type).firstOrNull,
      consent,
    ))
      consent,
};

bool _grantedCurrent(Map<String, dynamic>? newest, LegalConsent consent) {
  if (newest == null || newest['action'] != 'granted') return false;
  final version = newest['notice_version'];
  return version is String && version.compareTo(consent.version) >= 0;
}

abstract interface class LegalConsentRepository {
  /// The agreements the athlete has to give again before the app opens.
  Future<Set<LegalConsent>> loadOutdated();

  /// Records a grant of each of [consents] at the version this build shows.
  Future<void> grant(Set<LegalConsent> consents);
}

class SupabaseLegalConsentRepository implements LegalConsentRepository {
  SupabaseLegalConsentRepository(
    this._client, {
    this.callTimeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;

  /// How long a call may take before it counts as failed.
  final Duration callTimeout;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    return user.id;
  }

  @override
  Future<Set<LegalConsent>> loadOutdated() async {
    final rows = await _client
        .from('consent_records')
        .select('consent_type,notice_version,action')
        .eq('user_id', _userId)
        .inFilter('consent_type', [
          for (final consent in LegalConsent.values) consent.type,
        ])
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .timeout(callTimeout);
    return outdatedLegalConsents(rows);
  }

  @override
  Future<void> grant(Set<LegalConsent> consents) async {
    if (consents.isEmpty) return;
    final userId = _userId;
    await _client
        .from('consent_records')
        .insert([
          for (final consent in consents)
            {
              'user_id': userId,
              'consent_type': consent.type,
              'notice_version': consent.version,
              'action': 'granted',
              'source': 'ios_app',
            },
        ])
        .timeout(callTimeout);
  }
}

/// Opens a legal page in the in-app browser, or Safari when that cannot
/// open. A page that opens nowhere says where it lives.
Future<void> openLegalPage(BuildContext context, Uri url) async {
  var opened = false;
  try {
    opened = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    logNonCritical(e, 'Legal page not opened');
  }
  if (opened || !context.mounted) return;
  TracendToast.show(
    context,
    'The page did not open. It is at ${url.host}${url.path}',
    icon: CupertinoIcons.info,
  );
}

/// The three agreements, each its own unticked row: the beta terms and the
/// privacy notice, each with a link to its page, and explicit consent to
/// health-data processing. Used by onboarding and by the screen that asks
/// again after a page changes.
class LegalConsentRows extends StatelessWidget {
  const LegalConsentRows({
    required this.checked,
    required this.onChanged,
    super.key,
  });

  final Set<LegalConsent> checked;
  final void Function(LegalConsent consent, bool checked) onChanged;

  @override
  Widget build(BuildContext context) => TracendGroupedList(
    children: [
      _LegalCheckRow(
        title: 'I accept the private-beta terms',
        checked: checked.contains(LegalConsent.terms),
        onChanged: (value) => onChanged(LegalConsent.terms, value),
        linkLabel: 'Read the beta terms',
        url: LegalNotices.termsUrl,
      ),
      _LegalCheckRow(
        title: 'I have read the privacy notice',
        checked: checked.contains(LegalConsent.privacy),
        onChanged: (value) => onChanged(LegalConsent.privacy, value),
        linkLabel: 'Read the privacy notice',
        url: LegalNotices.privacyUrl,
      ),
      _LegalCheckRow(
        title: 'I agree to Tracend using my health data',
        detail:
            'My Apple Health data, check-ins, pain reports, body measurements '
            'and photos, used to coach me as the privacy notice describes.',
        checked: checked.contains(LegalConsent.healthData),
        onChanged: (value) => onChanged(LegalConsent.healthData, value),
      ),
    ],
  );
}

/// A check row with an optional link under its title. The row toggles the
/// check; the link is its own target, and VoiceOver reads the check and the
/// link as two elements.
class _LegalCheckRow extends StatelessWidget {
  const _LegalCheckRow({
    required this.title,
    required this.checked,
    required this.onChanged,
    this.detail,
    this.linkLabel,
    this.url,
  });

  final String title;
  final String? detail;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String? linkLabel;
  final Uri? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = this.detail;
    final linkLabel = this.linkLabel;
    final url = this.url;
    return InkWell(
      onTap: () => onChanged(!checked),
      excludeFromSemantics: true,
      highlightColor: context.tracendColors.surfaceRaised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TracendListRow.minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      container: true,
                      checked: checked,
                      button: true,
                      label: detail == null ? title : '$title. $detail',
                      onTap: () => onChanged(!checked),
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.bodyLarge),
                          if (detail != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.tracendColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (linkLabel != null && url != null)
                      Semantics(
                        link: true,
                        child: TextButton(
                          onPressed: () => openLegalPage(context, url),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 44),
                            alignment: Alignment.centerLeft,
                          ),
                          child: Text(linkLabel),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              CheckMark(checked: checked),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks an athlete who already finished setup to agree again after the beta
/// terms or privacy notice changed (or to a consent added since they agreed).
/// It blocks the app until all three rows are ticked; nothing is recorded
/// without the tap on Agree. Signing out and deleting the account stay open.
class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({
    required this.repository,
    required this.outdated,
    required this.onAgreed,
    required this.onSignOut,
    required this.deletion,
    super.key,
  });

  final LegalConsentRepository repository;

  /// The agreements to record; the rows ask for all three either way.
  final Set<LegalConsent> outdated;
  final VoidCallback onAgreed;

  /// Signs out; also runs once a deletion settles.
  final Future<void> Function() onSignOut;

  /// Deletes the account through the same sheet as Account.
  final AccountDeletionRepository deletion;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  final _checked = <LegalConsent>{};
  bool _busy = false;
  String? _error;

  bool get _allChecked => _checked.length == LegalConsent.values.length;

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.grant(widget.outdated);
      if (mounted) widget.onAgreed();
    } catch (e) {
      logNonCritical(e, 'Legal consent not recorded');
      if (mounted) {
        setState(
          () => _error =
              'Your agreement was not saved. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final outcome = await showTracendSheet<AccountDeletionOutcome>(
      context,
      title: 'Delete account',
      builder: (_) => AccountDeletionSheet(repository: widget.deletion),
    );
    if (outcome == null || !mounted) return;
    // The toast sits in the root overlay, so it outlives this screen.
    TracendToast.show(
      context,
      outcome == AccountDeletionOutcome.deleted
          ? 'Your account was deleted'
          : 'Signed out. Sign in to see whether the account remains.',
      icon: outcome == AccountDeletionOutcome.deleted
          ? CupertinoIcons.checkmark_alt
          : CupertinoIcons.info,
    );
    await _signOut();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and privacy')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(TracendSpacing.gutter),
          children: [
            Text(
              'Please agree again to carry on.',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'The beta terms or the privacy notice changed since you last '
              'agreed. Read them, then tick each row.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: TracendSpacing.lg),
            LegalConsentRows(
              checked: _checked,
              onChanged: (consent, value) => setState(() {
                if (value) {
                  _checked.add(consent);
                } else {
                  _checked.remove(consent);
                }
              }),
            ),
            const SizedBox(height: TracendSpacing.lg),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: colors.stateDanger)),
              const SizedBox(height: TracendSpacing.sm),
            ],
            FilledButton(
              onPressed: _busy || !_allChecked ? null : _agree,
              child: const Text('Agree and continue'),
            ),
            const SizedBox(height: TracendSpacing.md),
            Text(
              'If you do not agree, you can sign out, or delete your account '
              'and everything saved in it.',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: TracendSpacing.xs),
            TextButton(
              onPressed: _busy ? null : _signOut,
              child: const Text('Sign out'),
            ),
            TextButton(
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: colors.stateDanger),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
  }
}
