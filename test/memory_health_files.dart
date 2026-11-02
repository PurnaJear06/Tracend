import 'dart:io';

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

/// Files whose writes fail, as when the disk is full, and whose removals fail
/// when [failDeletes] is set; [failListing] makes listing fail. With [failWrites]
/// off only the others fail.
class FailingHealthFiles implements LocalHealthFiles {
  FailingHealthFiles(
    this._inner, {
    this.failWrites = true,
    this.failDeletes = false,
    this.failListing = false,
  });

  final LocalHealthFiles _inner;
  final bool failWrites;
  final bool failDeletes;
  final bool failListing;

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> write(String name, String contents) => failWrites
      ? throw const FileSystemException('disk full')
      : _inner.write(name, contents);

  @override
  Future<void> delete(String name) => failDeletes
      ? throw const FileSystemException('cannot delete')
      : _inner.delete(name);

  @override
  Future<List<String>> names() => failListing
      ? throw const FileSystemException('cannot list')
      : _inner.names();
}
