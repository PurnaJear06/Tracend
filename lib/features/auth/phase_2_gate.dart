import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/features/account/account_time_zone.dart';
import 'package:tracend/features/auth/account_session.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/shell/app_shell.dart';

class Phase2Gate extends StatefulWidget {
  const Phase2Gate({
    required this.environment,
    this.client,
    this.localData,
    super.key,
  });

  final AppEnvironment environment;

  /// The app's Supabase client unless a test provides one.
  final SupabaseClient? client;
  final LocalAccountData? localData;

  @override
  State<Phase2Gate> createState() => _Phase2GateState();
}

class _Phase2GateState extends State<Phase2Gate> {
  bool _loading = true;
  bool _authenticated = false;
  bool _onboardingComplete = false;
  AiCoachingConsentController? _aiConsent;

  /// One Apple Health repository for onboarding and the app; its state is
  /// kept per signed-in athlete.
  HealthRepository? _health;

  /// The athlete's usual months from Apple Health, sent at most once a month.
  HealthBaselineSource? _baseline;
  String? _error;
  StreamSubscription<AuthState>? _authEvents;

  /// The athlete the gate last let in, for clearing their local data once
  /// Auth has already removed the session.
  String? _userId;

  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  late final LocalAccountData _localData =
      widget.localData ?? LocalAccountData();

  @override
  void initState() {
    super.initState();
    if (widget.environment.hasSupabaseConfiguration) {
      // A refresh token Auth refuses while the app is open (the account was
      // deleted elsewhere) removes the session; the athlete lands on sign-in.
      _authEvents = _client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedOut &&
            state.signOutReason != SignOutReason.userInitiated &&
            _authenticated) {
          unawaited(_endRejectedSession(_userId, accountDeleted: false));
        }
      }, onError: (Object _) {});
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
      final client = _client;
      final session = client.auth.currentSession;
      if (session == null) {
        setState(() {
          _authenticated = false;
          _onboardingComplete = false;
        });
      } else {
        final userId = session.user.id;
        try {
          if (session.isExpired) await client.auth.refreshSession();
          // An access token stays valid for up to an hour after its user is
          // deleted, and the database checks only its signature. Auth says
          // whether the account and this session still exist.
          await client.auth.getUser();
        } on AuthException catch (error) {
          if (!isRejectedSession(error)) rethrow;
          await _endRejectedSession(
            userId,
            accountDeleted: isDeletedUser(error),
          );
          return;
        }
        _userId = userId;
        // Local dates on the server follow the device's time zone.
        await AccountTimeZone.supabase(client).sync();
        final repository = SupabaseOnboardingRepository(client);
        final complete = await repository.isOnboardingComplete();
        final aiConsent = _aiConsent ??= AiCoachingConsentController(
          SupabaseAiCoachingConsentRepository(client),
        );
        await aiConsent.load();
        // The usual months a later plan review compares with; never blocks.
        if (complete) unawaited(_baselineSource().refreshIfDue());
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

  /// Ends the session Auth refused and shows sign-in, with no network
  /// needed; a deleted account's local data goes too.
  Future<void> _endRejectedSession(
    String? userId, {
    required bool accountDeleted,
  }) async {
    await endRejectedSession(
      _client,
      _localData,
      userId,
      accountDeleted: accountDeleted,
    );
    _userId = null;
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _onboardingComplete = false;
      _error = null;
      _loading = false;
    });
  }

  HealthBaselineSource _baselineSource() => _baseline ??=
      SupabaseHealthBaselineSource(_client, SharedPreferencesAsync());

  @override
  void dispose() {
    _authEvents?.cancel();
    _aiConsent?.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await _client.auth.signOut(scope: SignOutScope.local);
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
    final aiConsent = _aiConsent!;
    final health = _health ??= SupabaseHealthRepository(
      _client,
      SharedPreferencesAsync(),
    );
    if (!_onboardingComplete) {
      return OnboardingFlow(
        repository: SupabaseOnboardingRepository(_client),
        onCompleted: _refresh,
        aiConsent: aiConsent,
        health: health,
        healthBaseline: _baselineSource(),
        onSignOut: _signOut,
      );
    }
    // Accounts created before the question existed, and anyone asked again
    // after a notice change, answer once before the app opens.
    if (aiConsent.choice == AiCoachingChoice.undecided) {
      return AiCoachingConsentScreen(
        controller: aiConsent,
        onDecided: () => setState(() {}),
      );
    }
    return AppShell(
      environment: widget.environment,
      onSignOut: _signOut,
      aiConsent: aiConsent,
      health: health,
    );
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
