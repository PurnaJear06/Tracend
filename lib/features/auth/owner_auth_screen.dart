import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

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
            _notice = 'Check your email to confirm this development account.';
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
      setState(() => _error = _safeAuthMessage(error));
    } catch (_) {
      setState(() {
        _error =
            'Sign-in could not be completed. Check the connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _safeAuthMessage(AuthException error) {
    if (error.statusCode == '400') {
      return _createAccount
          ? 'This account could not be created. Check the email and password.'
          : 'The email or password is incorrect.';
    }
    return 'Authentication is unavailable right now. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TracendSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      CupertinoIcons.waveform_path_ecg,
                      size: 44,
                      color: context.tracendColors.actionPrimary,
                      semanticLabel: 'Tracend',
                    ),
                    const SizedBox(height: TracendSpacing.lg),
                    Text(
                      'Your plan, explained by your data.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: TracendSpacing.sm),
                    Text(
                      'Owner development access',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TracendSpacing.xl),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign in')),
                        ButtonSegment(
                          value: true,
                          label: Text('Create account'),
                        ),
                      ],
                      selected: {_createAccount},
                      onSelectionChanged: _submitting
                          ? null
                          : (selection) => setState(() {
                              _createAccount = selection.single;
                              _error = null;
                              _notice = null;
                            }),
                    ),
                    const SizedBox(height: TracendSpacing.lg),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        helperText:
                            'Used only by Supabase Auth for this account.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.contains('@')
                            ? null
                            : 'Enter a valid email address.';
                      },
                    ),
                    const SizedBox(height: TracendSpacing.md),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'Use at least 8 characters.',
                        border: const OutlineInputBorder(),
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.tracendColors.stateDanger,
                              ),
                        ),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: TracendSpacing.md),
                      Semantics(liveRegion: true, child: Text(_notice!)),
                    ],
                    const SizedBox(height: TracendSpacing.lg),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_createAccount ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: TracendSpacing.md),
                    Text(
                      'Sign in with Apple remains deferred until external beta distribution.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
