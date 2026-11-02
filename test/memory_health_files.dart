import 'package:tracend/shared/local_health_store.dart';

/// The health cache's files held in memory, which every test starts with
/// (`flutter_test_config.dart`).
class MemoryHealthFiles implements LocalHealthFiles {
  final _files = <String, String>{};

  @override
  Future<String?> read(String name) async => _files[name];

  @override
  Future<void> write(String name, String contents) async {
    _files[name] = contents;
  }

  @override
  Future<void> delete(String name) async => _files.remove(name);

  @override
  Future<List<String>> names() async => _files.keys.toList();
}

/// Puts [values] (text or lists of text) in the health cache, as an earlier
/// run of the app would have left them.
Future<void> seedHealthCache(Map<String, Object> values) async {
  const store = LocalHealthStore();
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) {
      await store.setString(entry.key, value);
    } else {
      await store.setStringList(entry.key, List<String>.from(value as List));
    }
  }
}
