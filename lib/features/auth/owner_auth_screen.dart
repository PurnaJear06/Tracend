import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/auth/password_reset_flow.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// Email sign-in for the private beta: the brand mark, "Sign in to Tracend",
/// and one small line saying how this beta signs in. A forgotten password is
/// reset in the app with a code from email, and a confirmation email can be
/// sent again. Sign in with Apple replaces it before external distribution
/// (ADR 0002).
class OwnerAuthScreen extends StatefulWidget {
  const OwnerAuthScreen({required this.onAuthenticated, this.auth, super.key});

  final VoidCallback onAuthenticated;

  /// The app's Supabase Auth client unless a test provides one.
  final GoTrueClient? auth;

  @override
  State<OwnerAuthScreen> createState() => _OwnerAuthScreenState();
}

class _OwnerAuthScreenState extends State<OwnerAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscurePassword = true;
  bool _submitting = false;

  /// The password reset is open in place of the form.
  bool _resetting = false;
  String? _error;
  String? _notice;

  /// The address whose confirmation email can be sent again: the one just
  /// signed up, or one that signed in before confirming.
  String? _resendEmail;
  final _resendCooldown = ResendCooldown();
  bool _resending = false;

  GoTrueClient get _auth => widget.auth ?? Supabase.instance.client.auth;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _resendCooldown.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final email = _emailController.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
      _resendEmail = null;
    });

    try {
      if (_createAccount) {
        final result = await _auth.signUp(
          email: email,
          password: _passwordController.text,
        );
        if (result.session == null) {
          // Auth has just sent the email, so a second one waits a minute.
          _resendCooldown.start();
          setState(() {
            _notice = 'Check your email to confirm your account.';
            _resendEmail = email;
          });
          return;
        }
      } else {
        await _auth.signInWithPassword(
          email: email,
          password: _passwordController.text,
        );
      }
      widget.onAuthenticated();
    } on AuthException catch (error) {
      setState(() {
        _error = authErrorMessage(error, createAccount: _createAccount);
        if (error.code == 'email_not_confirmed') _resendEmail = email;
      });
    } catch (e) {
      logNonCritical(e);
      setState(() {
        _error =
            'Sign-in could not be completed. Check the connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Sends the confirmation email again, at most once a minute.
  Future<void> _resend() async {
    final email = _resendEmail;
    if (email == null || _resending || _resendCooldown.waiting) return;
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      await _auth.resend(type: OtpType.signup, email: email);
      _resendCooldown.start();
      if (mounted) {
        setState(
          () => _notice =
              'We sent the email again. Check your inbox and spam folder.',
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      final limited = isAuthRateLimit(error);
      if (limited) _resendCooldown.start();
      setState(() {
        _error = limited
            ? 'Too many requests. Wait a minute, then try again.'
            : error is AuthRetryableFetchException && error.statusCode == null
            ? 'The email could not be sent. Check the connection and try '
                  'again.'
            : 'The email could not be sent. Try again in a minute.';
      });
    } catch (e) {
      logNonCritical(e, 'confirmation email not sent again');
      if (mounted) {
        setState(
          () => _error =
              'The email could not be sent. Check the connection and try '
              'again.',
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _openReset() {
    if (_submitting) return;
    setState(() {
      _resetting = true;
      _error = null;
      _notice = null;
      _resendEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final light = Theme.of(context).brightness == Brightness.light;
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
    final mark = Center(
      child: TracendMark(
        size: 72,
        letterColor: light ? colors.textPrimary : TracendBrandColors.chalk,
        semanticLabel: null,
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              TracendSpacing.xl,
              gutter,
              TracendSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _resetting
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        mark,
                        const SizedBox(height: TracendSpacing.lg),
                        PasswordResetFlow(
                          auth: _auth,
                          initialEmail: _emailController.text,
                          onCancel: () => setState(() => _resetting = false),
                          onPasswordChanged: widget.onAuthenticated,
                        ),
                      ],
                    )
                  : _form(context, mark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, Widget mark) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mark,
            const SizedBox(height: TracendSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                _createAccount
                    ? 'Create your Tracend account'
                    : 'Sign in to Tracend',
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Your plan, explained by your data.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: TracendSpacing.xl),
            TracendSegmentedControl<bool>(
              segments: const [(false, 'Sign in'), (true, 'Create account')],
              selected: _createAccount,
              onChanged: (value) {
                if (_submitting) return;
                setState(() {
                  _createAccount = value;
                  _error = null;
                  _notice = null;
                  _resendEmail = null;
                });
              },
            ),
            const SizedBox(height: TracendSpacing.lg),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = value?.trim() ?? '';
                return email.contains('@')
                    ? null
                    : 'Enter a valid email address.';
              },
            ),
            const SizedBox(height: TracendSpacing.sm),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _createAccount ? 'At least 8 characters.' : null,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                ),
              ),
              obscureText: _obscurePassword,
              autofillHints: [
                _createAccount
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : 'Password must contain at least 8 characters.',
            ),
            if (_error != null) ...[
              const SizedBox(height: TracendSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.stateDanger,
                  ),
                ),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: TracendSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(_notice!, style: textTheme.bodyMedium),
              ),
            ],
            if (_resendEmail != null)
              ListenableBuilder(
                listenable: _resendCooldown,
                builder: (context, _) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed:
                        _resending || _submitting || _resendCooldown.waiting
                        ? null
                        : _resend,
                    child: Text(
                      _resendCooldown.waiting
                          ? 'Resend email in '
                                '${_resendCooldown.secondsLeft}s'
                          : 'Resend email',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: TracendSpacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? TracendLoader(
                      size: 24,
                      semanticLabel: _createAccount
                          ? 'Creating your account'
                          : 'Signing in',
                    )
                  : Text(_createAccount ? 'Create account' : 'Sign in'),
            ),
            if (!_createAccount) ...[
              const SizedBox(height: TracendSpacing.xs),
              TextButton(
                onPressed: _submitting ? null : _openReset,
                child: const Text('Forgot password?'),
              ),
            ],
            const SizedBox(height: TracendSpacing.lg),
            Text(
              'Private beta: email sign-in',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The message shown for a refused sign-in or sign-up. Sign-ups are
/// invite-only: the database refuses an email that is not on the invite list,
/// and Auth reports that as an unexpected failure (HTTP 500). Auth's own
/// codes say more than its status (a wrong password and an unconfirmed email
/// are both 400, a closed sign-up and a weak password both 422).
@visibleForTesting
String authErrorMessage(AuthException error, {required bool createAccount}) {
  if (createAccount &&
      (error.statusCode == '500' || error.code == 'unexpected_failure')) {
    return "This email isn't on the invite list yet.";
  }
  switch (error.code) {
    case 'email_not_confirmed':
      return 'Confirm your email first: open the message Tracend sent you, then sign in.';
    case 'signup_disabled':
      return 'New accounts are closed during the private beta.';
    case 'email_exists' || 'user_already_exists':
      return 'An account with this email already exists. Sign in instead.';
    case 'weak_password':
      return 'Choose a stronger password of at least 8 characters.';
    case 'email_address_invalid':
      return 'Check the email address.';
    case 'over_request_rate_limit' ||
        'over_email_send_rate_limit' ||
        'over_sms_send_rate_limit':
      return 'Too many attempts. Wait a minute, then try again.';
  }
  if (error.statusCode == '429') {
    return 'Too many attempts. Wait a minute, then try again.';
  }
  if (error.statusCode == '400' || error.statusCode == '422') {
    return createAccount
        ? 'This account could not be created. Check the email and password.'
        : 'The email or password is incorrect.';
  }
  return 'Authentication is unavailable right now. Try again.';
}
