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
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/shared/brand/tracend_intro.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

class Phase2Gate extends StatefulWidget {
  const Phase2Gate({
    required this.environment,
    this.client,
    this.localData,
    this.liveActivity = const MethodChannelWorkoutActivityBridge(),
    this.homeWidgets = const MethodChannelHomeWidgetBridge(),
    super.key,
  });

  final AppEnvironment environment;

  /// The app's Supabase client unless a test provides one.
  final SupabaseClient? client;

  /// The workout rest's Live Activity, ended on every signed-out transition
  /// so no rest outlives its athlete on the Lock Screen.
  final WorkoutActivityBridge liveActivity;

  /// The Home Screen and Lock Screen widgets, emptied on every signed-out
  /// transition so no widget keeps a signed-out athlete's day.
  final HomeWidgetBridge homeWidgets;
  final LocalAccountData? localData;

  @override
  State<Phase2Gate> createState() => _Phase2GateState();
}

class _Phase2GateState extends State<Phase2Gate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _authenticated = false;
  bool _onboardingComplete = false;

  /// The app is open from the plan this phone saved, because the account
  /// could not be checked: no connection, or one too slow to wait for. Only
  /// the plan and the workout work; leaving it takes a successful check.
  bool _offline = false;

  /// An account check is running.
  bool _checking = false;
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

  /// Counts the sessions that ended. A refresh that began before one ended
  /// belongs to a session that is gone and commits nothing.
  int _sessionsEnded = 0;

  /// How long a cold start waits for the account check before it opens the
  /// saved plan, when it has one.
  static const _waitForNetwork = Duration(seconds: 6);

  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  late final TrainingHubCache _savedPlan = TrainingHubCache(
    SharedPreferencesAsync(),
  );
  late final LocalAccountData _localData =
      widget.localData ?? LocalAccountData();
  late final HomeWidgetEraser _widgetEraser = HomeWidgetEraser(
    widget.homeWidgets,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_widgetEraser.retryPending());
    if (widget.environment.hasSupabaseConfiguration) {
      _authEvents = _client.auth.onAuthStateChange.listen((state) {
        if (state.event != AuthChangeEvent.signedOut) return;
        // Every way a session ends passes here, whichever screen asked for
        // it (or none did: a deletion settling after its sheet was closed):
        // no rest activity or widget keeps the athlete's day, and the
        // athlete lands on sign-in.
        _clearSessionOutputs();
        final userId = _userId;
        final refused =
            state.signOutReason != SignOutReason.userInitiated &&
            _authenticated;
        _showSignedOut();
        // A refresh token Auth refuses while the app is open (the account
        // was deleted elsewhere) removes the session.
        if (refused) {
          unawaited(_endRejectedSession(userId, accountDeleted: false));
        }
      }, onError: (Object _) {});
      _refresh();
    } else {
      _loading = false;
    }
  }

  /// Checks the stored session and the account, then opens the app. With
  /// [quiet] (a retry from the offline app) nothing is replaced by the
  /// loader and a failure changes nothing: the app stays open on the saved
  /// plan.
  Future<void> _refresh({bool quiet = false}) async {
    if (quiet && _checking) return;
    final sessionsEnded = _sessionsEnded;
    bool ended() => !mounted || sessionsEnded != _sessionsEnded;
    _checking = true;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    String? userId;
    try {
      final client = _client;
      final session = client.auth.currentSession;
      if (session == null) {
        // A widget snapshot a failed clear left behind goes now.
        unawaited(_emptyWidgets());
        setState(() {
          _authenticated = false;
          _onboardingComplete = false;
          _offline = false;
        });
      } else {
        userId = session.user.id;
        final check = _checkAccount(client, session, ended);
        if (_offline) {
          await check;
        } else {
          try {
            await check.timeout(_waitForNetwork);
          } on TimeoutException {
            // A connection too slow to wait for: the saved plan opens now
            // and the check finishes behind it.
            if (ended()) return;
            if (!await _openSaved(userId, ended)) await check;
          }
        }
      }
    } catch (e, stackTrace) {
      // Seen in Sentry by type and code: a gate that cannot load the account
      // leaves the athlete on "Connection needed", or on the saved plan.
      if (_offline) {
        logNonCritical(e, 'Account state not loaded');
      } else {
        reportNonCritical(e, stackTrace, 'Account state not loaded');
      }
      if (!ended() && !_offline && userId != null) {
        await _openSaved(userId, ended);
      }
      if (!ended() && !_offline && !quiet) {
        setState(() {
          _error =
              'The account state could not be loaded. Check the connection and retry.';
        });
      }
    } finally {
      _checking = false;
      if (!ended() && !quiet) setState(() => _loading = false);
    }
  }

  /// Asks Auth whether the account and session still exist, then opens the
  /// app on the account's state. Throws when that cannot be done; a session
  /// Auth refused is ended here.
  Future<void> _checkAccount(
    SupabaseClient client,
    Session session,
    bool Function() ended,
  ) async {
    final userId = session.user.id;
    try {
      if (session.isExpired) await client.auth.refreshSession();
      // An access token stays valid for up to an hour after its user is
      // deleted, and the database checks only its signature. Auth says
      // whether the account and this session still exist.
      await client.auth.getUser();
    } on AuthException catch (error) {
      if (!isRejectedSession(error)) rethrow;
      await _endRejectedSession(userId, accountDeleted: isDeletedUser(error));
      return;
    }
    if (ended()) return;
    // Local dates on the server follow the device's time zone.
    await AccountTimeZone.supabase(client).sync();
    if (ended()) return;
    final repository = SupabaseOnboardingRepository(client);
    final complete = await repository.isOnboardingComplete();
    if (ended()) return;
    final aiConsent = _aiConsent ??= AiCoachingConsentController(
      SupabaseAiCoachingConsentRepository(client),
    );
    // A notice that cannot be loaded turns AI coaching off here and
    // leaves the app open; the screens that ask retry it themselves.
    await aiConsent.load();
    if (ended()) return;
    _userId = userId;
    // The usual months a later plan review compares with; never blocks.
    if (complete) unawaited(_baselineSource().refreshIfDue());
    setState(() {
      _authenticated = true;
      _onboardingComplete = complete;
      _offline = false;
    });
  }

  /// Opens the app on the plan this phone saved for [userId], when it has
  /// one: an athlete who had a plan has finished onboarding. False when
  /// there is none, so the gate says a connection is needed.
  Future<bool> _openSaved(String userId, bool Function() ended) async {
    final saved = await _savedPlan.load(userId);
    if (saved == null || ended()) return false;
    _aiConsent ??= AiCoachingConsentController(
      SupabaseAiCoachingConsentRepository(_client),
    );
    _userId = userId;
    setState(() {
      _authenticated = true;
      _onboardingComplete = true;
      _offline = true;
      _error = null;
      _loading = false;
    });
    return true;
  }

  /// Leaves the app for sign-in: a refresh still running is dropped, and
  /// the gate's transient state (loading, a connection error) goes with the
  /// session, so nothing hides sign-in. Repeated events change nothing more.
  void _showSignedOut() {
    if (!mounted) return;
    _sessionsEnded++;
    setState(() {
      _authenticated = false;
      _onboardingComplete = false;
      _offline = false;
      _userId = null;
      _error = null;
      _loading = false;
    });
  }

  /// Ends the rest's Live Activity and empties the widgets. Runs on every
  /// signed-out transition, whichever screen ended the session. (The shell's
  /// publisher also clears the snapshot as it goes away; both go through the
  /// same eraser logic, and a launch with no session clears again.)
  void _clearSessionOutputs() {
    unawaited(widget.liveActivity.end());
    unawaited(_emptyWidgets());
  }

  /// Empties the widgets; a clear that fails for good is kept and retried
  /// on every launch and resume (`HomeWidgetEraser`).
  Future<void> _emptyWidgets() => _widgetEraser.erase();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_widgetEraser.retryPending());
      // Travel changes the device's zone while the app sleeps: the server's
      // local dates follow the stored zone, so it is stored again now. The
      // screens refresh after it (this observer runs before theirs), or they
      // would read the old local date and mark it fresh.
      if (_authenticated && widget.environment.hasSupabaseConfiguration) {
        ResumeGate.hold(AccountTimeZone.supabase(_client).sync());
        // Back at the front with the saved plan open: the connection may be
        // back too.
        if (_offline) unawaited(_refresh(quiet: true));
      }
    }
  }

  /// Ends the session Auth refused, with no network needed; a deleted
  /// account's local data goes too. The auth listener shows sign-in.
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
  }

  HealthBaselineSource _baselineSource() => _baseline ??=
      SupabaseHealthBaselineSource(_client, SharedPreferencesAsync());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authEvents?.cancel();
    _widgetEraser.dispose();
    _aiConsent?.dispose();
    super.dispose();
  }

  /// Signing out, and the end of an account deletion (Account calls this
  /// once the deletion settles). The auth listener shows sign-in.
  Future<void> _signOut() async {
    await signOutAthlete(_client, _localData, _userId);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.environment.hasSupabaseConfiguration) {
      return AppShell(
        environment: widget.environment,
        homeWidgets: widget.homeWidgets,
      );
    }
    if (!widget.environment.usesOwnerEmailPassword) {
      return const _GateMessage(
        title: 'Authentication mode unavailable',
        message:
            'This build supports owner email/password authentication only.',
      );
    }
    // The intro plays once, on this cold start, while the stored session is
    // restored; later refreshes (sign-in, sign-out) show the loader alone.
    return TracendIntro(ready: !_loading, child: _sessionContent());
  }

  Widget _sessionContent() {
    if (_loading) return const _GateLoading();
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
    // after a notice change, answer once before the app opens. Without a
    // notice from the server there is nothing to answer: the app opens with
    // AI coaching off.
    if (aiConsent.choice == AiCoachingChoice.undecided &&
        aiConsent.notice != null) {
      return AiCoachingConsentScreen(
        controller: aiConsent,
        onDecided: () => setState(() {}),
      );
    }
    return AppShell(
      // One shell per athlete: its widget publisher follows their choice.
      key: ValueKey(_userId),
      environment: widget.environment,
      onSignOut: _signOut,
      aiConsent: aiConsent,
      health: health,
      homeWidgets: widget.homeWidgets,
      widgetEraser: _widgetEraser,
      userId: _userId,
      offline: _offline,
      onRetryConnection: () => _refresh(quiet: true),
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: TracendLoader(size: 36, semanticLabel: 'Restoring your session'),
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
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
