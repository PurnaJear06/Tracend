import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// The files behind [LocalHealthStore]: one named file per key, in a folder
/// that is out of iCloud and computer backups
/// (`ios/Runner/Native/LocalHealthStoreBridge.swift`). Tests install a copy
/// in memory.
abstract interface class LocalHealthFiles {
  /// The files the app uses.
  static LocalHealthFiles instance = NativeLocalHealthFiles();

  /// The contents of [name], or null when there is no such file.
  Future<String?> read(String name);

  /// Replaces [name] with [contents] in one step.
  Future<void> write(String name, String contents);

  /// Removes [name]; nothing happens when there is no such file.
  Future<void> delete(String name);

  /// The names of every file kept.
  Future<List<String>> names();
}

/// What this phone caches of an athlete's health so the app works with no
/// connection: pain reports and check-ins waiting to be sent, workout drafts
/// and exercise history, the saved plan, the referrals read, and the Coach
/// thread last open.
///
/// These are files, not `SharedPreferences`: preferences live in a plist that
/// iCloud Backup and computer backups copy. The files are out of both and
/// protected until the phone's first unlock (SECURITY_PRIVACY §8). The
/// methods mirror `SharedPreferencesAsync`, so a cache moves over by changing
/// its store. A key is any text; it is escaped into a file name.
class LocalHealthStore {
  const LocalHealthStore({LocalHealthFiles? files}) : _files = files;

  final LocalHealthFiles? _files;

  LocalHealthFiles get _backing => _files ?? LocalHealthFiles.instance;

  static const _extension = '.hc';

  static String _fileName(String key) {
    final escaped = Uri.encodeComponent(key);
    final safe = escaped.startsWith('.')
        ? '%2E${escaped.substring(1)}'
        : escaped;
    return '$safe$_extension';
  }

  Future<String?> getString(String key) => _backing.read(_fileName(key));

  Future<void> setString(String key, String value) =>
      _backing.write(_fileName(key), value);

  /// The list kept for [key], or null when none is kept or it is not a list
  /// of text.
  Future<List<String>?> getStringList(String key) async {
    final stored = await getString(key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        return null;
      }
      return List<String>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> setStringList(String key, List<String> value) =>
      setString(key, jsonEncode(value));

  Future<void> remove(String key) => _backing.delete(_fileName(key));

  /// Removes each of [keys] that is kept.
  Future<void> removeAll(Iterable<String> keys) async {
    for (final key in keys) {
      await remove(key);
    }
  }

  /// Every key kept.
  Future<Set<String>> getKeys() async => {
    for (final name in await _backing.names())
      if (name.endsWith(_extension))
        Uri.decodeComponent(name.substring(0, name.length - _extension.length)),
  };
}

/// The folder the native side prepared, read and listed with `dart:io`.
/// Writing goes through the channel, so the native side sets each file's
/// protection and keeps the folder excluded from backups.
class NativeLocalHealthFiles implements LocalHealthFiles {
  static const _channel = MethodChannel('tracend/local_health_store');
  Future<Directory>? _folder;

  /// The folder; asked for again after a failure.
  Future<Directory> _directory() {
    final open = _folder ??= _channel
        .invokeMethod<String>('directory')
        .then((path) => Directory(path!));
    return open.catchError((Object error) {
      _folder = null;
      throw error;
    });
  }

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  @override
  Future<String?> read(String name) async {
    final file = await _file(name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String name, String contents) async {
    await _directory();
    await _channel.invokeMethod<bool>('write', {
      'name': name,
      'contents': contents,
    });
  }

  @override
  Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> names() async => [
    await for (final entity in (await _directory()).list())
      if (entity is File) entity.uri.pathSegments.last,
  ];
}
