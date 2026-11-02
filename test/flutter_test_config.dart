import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/local_health_store.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'memory_health_files.dart';

/// Runs before every test file. Shared widgets render without motion so the
/// suite's `pumpAndSettle` calls never wait on a looping skeleton shimmer.
/// A test that checks motion puts a `TracendMotionScope` in its tree. Each
/// test starts with an empty health cache held in memory, so none reaches the
/// phone's files.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TracendMotionScope.defaultLevel = TracendMotionLevel.static;
  setUp(() => LocalHealthFiles.instance = MemoryHealthFiles());
  await testMain();
}
