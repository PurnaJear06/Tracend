import 'dart:async';

import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Runs before every test file. Shared widgets render without motion so the
/// suite's `pumpAndSettle` calls never wait on a looping skeleton shimmer.
/// A test that checks motion puts a `TracendMotionScope` in its tree.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TracendMotionScope.defaultLevel = TracendMotionLevel.static;
  await testMain();
}
