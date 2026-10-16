/// One request per read while it is in flight.
///
/// Several screens ask a repository for the same data when they open. A
/// caller that arrives while the same read is running joins it instead of
/// sending a second request. A finished read is never reused, so nothing is
/// cached: the next caller asks the server again. A repository calls
/// [afterWrite] around its writes so that no read started before a write
/// finished can be joined after it.
class SharedReads {
  final _inFlight = <Object, Future<Object?>>{};

  /// The running read for [key], or the one [read] starts.
  Future<T> join<T>(Object key, Future<T> Function() read) {
    final running = _inFlight[key];
    if (running != null) return running as Future<T>;
    final request = read();
    // A block body: whenComplete waits on a returned future, and remove()
    // returns this very request.
    late final Future<T> tracked;
    tracked = request.whenComplete(() {
      if (identical(_inFlight[key], tracked)) _inFlight.remove(key);
    });
    _inFlight[key] = tracked;
    return tracked;
  }

  /// Forgets every running read, so the next caller starts its own.
  void invalidate() => _inFlight.clear();

  /// Runs [write], then forgets the running reads whether it succeeded or
  /// not: a failed write may still have changed rows.
  Future<T> afterWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } finally {
      invalidate();
    }
  }
}
