import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/shell/app_shell.dart';

class Phase2Gate extends StatefulWidget {
  const Phase2Gate({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  State<Phase2Gate> createState() => _Phase2GateState();
}

class _Phase2GateState extends State<Phase2Gate> {
  bool _loading = true;
  bool _authenticated = false;
  bool _onboardingComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.environment.hasSupabaseConfiguration) {
      _refresh();
    } else {
      _loading = false;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      var session = client.auth.currentSession;
      if (session == null) {
        setState(() {
          _authenticated = false;
          _onboardingComplete = false;
        });
      } else {
        if (session.isExpired) {
          session = (await client.auth.refreshSession()).session;
        }
        if (session == null) {
          await client.auth.signOut(scope: SignOutScope.local);
          setState(() {
            _authenticated = false;
            _onboardingComplete = false;
          });
          return;
        }
        final repository = SupabaseOnboardingRepository(client);
        final complete = await repository.isOnboardingComplete();
        setState(() {
          _authenticated = true;
          _onboardingComplete = complete;
        });
      }
    } catch (e) {
      debugPrint('Non-critical error: $e');
      setState(() {
        _error =
            'The account state could not be loaded. Check the connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.environment.hasSupabaseConfiguration) {
      return AppShell(environment: widget.environment);
    }
    if (!widget.environment.usesOwnerEmailPassword) {
      return const _GateMessage(
        title: 'Authentication mode unavailable',
        message:
            'This build supports owner email/password authentication only.',
      );
    }
    if (_loading) {
      return const _GateMessage(
        title: 'Restoring your session',
        message: 'Checking your private account state…',
        loading: true,
      );
    }
    if (_error != null) {
      return _GateMessage(
        title: 'Connection needed',
        message: _error!,
        onRetry: _refresh,
      );
    }
    if (!_authenticated) {
      return OwnerAuthScreen(onAuthenticated: _refresh);
    }
    if (!_onboardingComplete) {
      return OnboardingFlow(
        repository: SupabaseOnboardingRepository(Supabase.instance.client),
        onCompleted: _refresh,
      );
    }
    return AppShell(environment: widget.environment, onSignOut: _signOut);
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.title,
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String title;
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                ],
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
