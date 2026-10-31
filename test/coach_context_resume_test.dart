import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';

/// Coach's starter questions follow what Coach can see. "Why don't I have a
/// plan yet?" must not outlive the plan's approval.
class _Repository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  bool planApproved = false;
  int contextLoads = 0;
  bool failLoads = false;

  @override
  Future<List<CoachContextSource>> loadContextStatus() async {
    contextLoads++;
    if (failLoads) throw StateError('offline');
    return [
      CoachContextSource(
        key: 'approved_plan',
        label: 'Approved training plan',
        available: planApproved,
        records: 0,
      ),
    ];
  }

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate({String? localDate}) =>
      throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
  @override
  Future<List<CoachThread>> loadThreads() async => const [];
  @override
  Future<String> createThread({bool remember = true}) async => 'thread-1';
  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];
  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) => throw StateError('not needed');
  @override
  Future<void> deleteThread(String threadId) async {}
}

class _NoMemory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;
  @override
  Future<void> remember(String threadId) async {}
}

void main() {
  late DateTime now;
  late _Repository repository;
  const noPlan = 'Why don’t I have a plan yet?';

  setUp(() {
    now = DateTime(2026, 10, 2, 9);
    repository = _Repository();
  });

  Future<void> pumpCoach(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: CoachScreen(
            repository: repository,
            threadMemory: _NoMemory(),
            active: active,
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resume refreshes the starter questions once a plan exists', (
    tester,
  ) async {
    await pumpCoach(tester);
    expect(find.text(noPlan), findsOneWidget);

    repository.planApproved = true;
    now = now.add(const Duration(minutes: 11));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(noPlan), findsNothing);
    expect(find.text('What is my next meal?'), findsOneWidget);
  });

  testWidgets('a context status under ten minutes old is kept on resume', (
    tester,
  ) async {
    await pumpCoach(tester);
    repository.planApproved = true;
    now = now.add(const Duration(minutes: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.contextLoads, 1);
  });

  testWidgets('opening the Coach tab again refreshes the starter questions', (
    tester,
  ) async {
    await pumpCoach(tester, active: false);
    repository.planApproved = true;
    now = now.add(const Duration(minutes: 2));
    await pumpCoach(tester);

    expect(find.text(noPlan), findsNothing);
    expect(repository.contextLoads, 2);
  });

  testWidgets('a context status that failed to load is asked again on the '
      'next resume, not kept as fresh', (tester) async {
    repository.failLoads = true;
    await pumpCoach(tester);
    expect(repository.contextLoads, 1);

    repository.failLoads = false;
    repository.planApproved = true;
    now = now.add(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.contextLoads, 2);
    expect(find.text(noPlan), findsNothing);
    expect(find.text('What is my next meal?'), findsOneWidget);
  });
}
