import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/diagnostics.dart';

/// Counts down the wait before an email can be asked for again. Auth sends
/// one email a minute to an address and refuses anything sooner.
class ResendCooldown extends ChangeNotifier {
  ResendCooldown({this.length = const Duration(seconds: 60)});

  final Duration length;
  Timer? _timer;
  int _secondsLeft = 0;

  int get secondsLeft => _secondsLeft;
  bool get waiting => _secondsLeft > 0;

  void start() {
    _timer?.cancel();
    _secondsLeft = length.inSeconds;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsLeft--;
      if (_secondsLeft <= 0) timer.cancel();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Whether Auth refused a request for coming too often.
bool isAuthRateLimit(AuthException error) =>
    error.statusCode == '429' ||
    error.code == 'over_request_rate_limit' ||
    error.code == 'over_email_send_rate_limit';

/// A forgotten password, reset in the app: the athlete asks for a code by
/// email, then types it with a new password. No link is involved, because
/// the app never takes a session from a link (`tracendAuthOptions`).
///
/// The app never says whether an email has an account: asking for a code
/// reads the same either way. Once the code is accepted the athlete is
/// signed in, and [onPasswordChanged] runs after the new password is saved.
class PasswordResetFlow extends StatefulWidget {
  const PasswordResetFlow({
    required this.auth,
    required this.initialEmail,
    required this.onCancel,
    required this.onPasswordChanged,
    super.key,
  });

  final GoTrueClient auth;
  final String initialEmail;

  /// Back to sign-in, with no password changed.
  final VoidCallback onCancel;
  final VoidCallback onPasswordChanged;

  @override
  State<PasswordResetFlow> createState() => _PasswordResetFlowState();
}

class _PasswordResetFlowState extends State<PasswordResetFlow> {
  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail.trim(),
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cooldown = ResendCooldown();

  /// The address the code was asked for; null until then.
  String? _email;

  /// The code was accepted, so this phone holds the account's session and
  /// only the new password is left to save.
  bool _verified = false;
  bool _obscurePassword = true;
  bool _working = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate() || _working) return;
    final email = _emailController.text.trim();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.auth.resetPasswordForEmail(email);
      _codeSent(email);
    } on AuthException catch (error) {
      if (_emailLimit(error)) {
        _codeSent(email);
      } else if (mounted) {
        setState(
          () => _error = isAuthRateLimit(error)
              ? 'Too many requests. Wait a minute, then try again.'
              : _sendFailure(error),
        );
      }
    } catch (e) {
      logNonCritical(e, 'password reset code not sent');
      if (mounted) setState(() => _error = _connectionFailure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Auth's limit on emails (one a minute to an address, and a cap an hour)
  /// is checked only for an address with an account: an unknown address is
  /// answered at once with nothing sent. So this refusal reads as sent, and
  /// the screen is the same either way. A limit on requests applies to
  /// everyone and is said as it is.
  static bool _emailLimit(AuthException error) =>
      error.code == 'over_email_send_rate_limit';

  void _codeSent(String email) {
    if (!mounted) return;
    _cooldown.start();
    setState(() => _email = email);
  }

  void _newCodeSent() {
    if (!mounted) return;
    _cooldown.start();
    setState(
      () =>
          _notice = 'If an account uses this email, a new code is on its way.',
    );
  }

  Future<void> _sendAgain() async {
    final email = _email;
    if (email == null || _working || _cooldown.waiting) return;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.auth.resetPasswordForEmail(email);
      _newCodeSent();
    } on AuthException catch (error) {
      if (!mounted) return;
      if (_emailLimit(error)) {
        _newCodeSent();
      } else {
        if (isAuthRateLimit(error)) _cooldown.start();
        setState(
          () => _error = isAuthRateLimit(error)
              ? 'Too many requests. Wait a minute, then send a new code.'
              : _sendFailure(error),
        );
      }
    } catch (e) {
      logNonCritical(e, 'password reset code not sent');
      if (mounted) setState(() => _error = _connectionFailure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setPassword() async {
    final email = _email;
    if (email == null || !_codeFormKey.currentState!.validate() || _working) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!_verified) {
        try {
          final verified = await widget.auth.verifyOTP(
            type: OtpType.recovery,
            email: email,
            token: _codeController.text.trim(),
          );
          if (verified.session == null) {
            throw const AuthException('No session for the code.');
          }
        } on AuthException catch (error) {
          if (mounted) setState(() => _error = _codeFailure(error));
          return;
        }
        if (!mounted) return;
        setState(() => _verified = true);
      }
      try {
        await widget.auth.updateUser(
          UserAttributes(password: _passwordController.text),
        );
      } on AuthException catch (error) {
        if (mounted) setState(() => _error = _passwordFailure(error));
        return;
      }
      widget.onPasswordChanged();
    } catch (e) {
      logNonCritical(e, 'password not reset');
      if (mounted) setState(() => _error = _connectionFailure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Leaves for sign-in. A code that was accepted signed this phone in, so
  /// that session ends here: the athlete signs in with a password they know.
  Future<void> _cancel() async {
    if (_verified) {
      try {
        await widget.auth.signOut(scope: SignOutScope.local);
      } catch (e) {
        logNonCritical(e);
      }
    }
    widget.onCancel();
  }

  static const _connectionFailure =
      'Password reset could not be completed. Check the connection and try '
      'again.';

  static String _sendFailure(AuthException error) {
    if (error is AuthRetryableFetchException && error.statusCode == null) {
      return 'The code could not be sent. Check the connection and try again.';
    }
    if (error.code == 'email_address_invalid' ||
        error.code == 'validation_failed') {
      return 'Check the email address.';
    }
    return 'Password reset is unavailable right now. Try again later.';
  }

  static String _codeFailure(AuthException error) {
    if (isAuthRateLimit(error)) {
      return 'Too many attempts. Wait a few minutes, then try again.';
    }
    if (error is AuthRetryableFetchException) {
      return 'The code could not be checked. Check the connection and try '
          'again.';
    }
    return 'That code is wrong or has expired. Check it, or send a new code.';
  }

  static String _passwordFailure(AuthException error) {
    if (error is AuthWeakPasswordException && error.reasons.contains('pwned')) {
      return 'This password has appeared in a data breach. Choose a '
          'different one.';
    }
    switch (error.code) {
      case 'weak_password':
        return 'Choose a stronger password of at least 8 characters.';
      case 'same_password':
        return 'Choose a password different from your old one.';
    }
    if (error is AuthRetryableFetchException) {
      return 'Your new password was not saved. Check the connection and try '
          'again.';
    }
    return 'Your new password was not saved. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: email == null ? _emailStep(context) : _codeStep(context, email),
    );
  }

  List<Widget> _emailStep(BuildContext context) {
    return [
      ..._heading(
        context,
        'Reset your password',
        'Enter the email you sign in with. If an account uses it, we will '
            'email it a code for setting a new password.',
      ),
      Form(
        key: _emailFormKey,
        child: TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _sendCode(),
          validator: (value) => (value?.trim() ?? '').contains('@')
              ? null
              : 'Enter a valid email address.',
        ),
      ),
      ..._messages(context),
      const SizedBox(height: TracendSpacing.lg),
      FilledButton(
        onPressed: _working ? null : _sendCode,
        child: _working
            ? const TracendLoader(size: 24, semanticLabel: 'Sending the code')
            : const Text('Send code'),
      ),
      const SizedBox(height: TracendSpacing.xs),
      TextButton(
        onPressed: _working ? null : _cancel,
        child: const Text('Back to sign in'),
      ),
    ];
  }

  List<Widget> _codeStep(BuildContext context, String email) {
    return [
      ..._heading(
        context,
        'Check your email',
        _verified
            ? 'Code accepted. Choose your new password.'
            : 'If an account uses $email, we sent it a code. Enter it here '
                  'with a new password. If nothing arrives in a few minutes, '
                  'check your spam folder or send a new code.',
      ),
      AutofillGroup(
        child: Form(
          key: _codeFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_verified) ...[
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code from the email',
                  ),
                  keyboardType: TextInputType.number,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value?.trim().length ?? 0) >= 6
                      ? null
                      : 'Enter the code from the email.',
                ),
                const SizedBox(height: TracendSpacing.sm),
              ],
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters.',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
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
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _setPassword(),
                validator: (value) => (value?.length ?? 0) >= 8
                    ? null
                    : 'Password must contain at least 8 characters.',
              ),
            ],
          ),
        ),
      ),
      ..._messages(context),
      const SizedBox(height: TracendSpacing.lg),
      FilledButton(
        onPressed: _working ? null : _setPassword,
        child: _working
            ? const TracendLoader(size: 24, semanticLabel: 'Saving')
            : const Text('Set new password'),
      ),
      if (!_verified) ...[
        const SizedBox(height: TracendSpacing.xs),
        ListenableBuilder(
          listenable: _cooldown,
          builder: (context, _) => TextButton(
            onPressed: _working || _cooldown.waiting ? null : _sendAgain,
            child: Text(
              _cooldown.waiting
                  ? 'Send a new code in ${_cooldown.secondsLeft}s'
                  : 'Send a new code',
            ),
          ),
        ),
      ],
      TextButton(
        onPressed: _working ? null : _cancel,
        child: const Text('Back to sign in'),
      ),
    ];
  }

  List<Widget> _heading(BuildContext context, String title, String body) {
    final textTheme = Theme.of(context).textTheme;
    return [
      Semantics(
        header: true,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium,
        ),
      ),
      const SizedBox(height: TracendSpacing.xs),
      Text(
        body,
        textAlign: TextAlign.center,
        style: textTheme.bodyLarge?.copyWith(
          color: context.tracendColors.textSecondary,
        ),
      ),
      const SizedBox(height: TracendSpacing.xl),
    ];
  }

  List<Widget> _messages(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return [
      if (_error != null) ...[
        const SizedBox(height: TracendSpacing.md),
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
      if (_notice != null) ...[
        const SizedBox(height: TracendSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(_notice!, style: textTheme.bodyMedium),
        ),
      ],
    ];
  }
}
