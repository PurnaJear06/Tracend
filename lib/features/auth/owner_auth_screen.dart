import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// Email sign-in for the private beta: the brand mark, "Sign in to Tracend",
/// and one small line saying how this beta signs in. Sign in with Apple
/// replaces it before external distribution (ADR 0002).
class OwnerAuthScreen extends StatefulWidget {
  const OwnerAuthScreen({required this.onAuthenticated, super.key});

  final VoidCallback onAuthenticated;

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
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (_createAccount) {
        final result = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (result.session == null) {
          setState(() {
            _notice = 'Check your email to confirm your account.';
          });
          return;
        }
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      widget.onAuthenticated();
    } on AuthException catch (error) {
      setState(
        () => _error = authErrorMessage(error, createAccount: _createAccount),
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      setState(() {
        _error =
            'Sign-in could not be completed. Check the connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final gutter = MediaQuery.sizeOf(context).width < 375
        ? TracendSpacing.md
        : TracendSpacing.gutter;
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
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: TracendMark(
                          size: 72,
                          letterColor: light
                              ? colors.textPrimary
                              : TracendBrandColors.chalk,
                          semanticLabel: null,
                        ),
                      ),
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
                        style: textTheme.bodyLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: TracendSpacing.xl),
                      TracendSegmentedControl<bool>(
                        segments: const [
                          (false, 'Sign in'),
                          (true, 'Create account'),
                        ],
                        selected: _createAccount,
                        onChanged: (value) {
                          if (_submitting) return;
                          setState(() {
                            _createAccount = value;
                            _error = null;
                            _notice = null;
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
                          helperText: _createAccount
                              ? 'At least 8 characters.'
                              : null,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
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
                            : Text(
                                _createAccount ? 'Create account' : 'Sign in',
                              ),
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      Text(
                        'Private beta: email sign-in',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The message shown for a refused sign-in or sign-up. Sign-ups are
/// invite-only: the database refuses an email that is not on the invite list,
/// and Auth reports that as an unexpected failure (HTTP 500).
@visibleForTesting
String authErrorMessage(AuthException error, {required bool createAccount}) {
  if (createAccount &&
      (error.statusCode == '500' || error.code == 'unexpected_failure')) {
    return "This email isn't on the invite list yet.";
  }
  if (error.statusCode == '400') {
    return createAccount
        ? 'This account could not be created. Check the email and password.'
        : 'The email or password is incorrect.';
  }
  return 'Authentication is unavailable right now. Try again.';
}
