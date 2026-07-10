import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openSecureExportUrl(Uri url) async {
  // iOS can report false after Safari has already accepted and opened a
  // download URL. A valid signed URL plus an exception-free handoff is the
  // reliable boundary; the server records the download before returning it.
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

class PrivacyExport {
  const PrivacyExport({
    required this.id,
    required this.status,
    this.byteSize,
    this.expiresAt,
    this.downloadCount = 0,
  });

  final String id;
  final String status;
  final int? byteSize;
  final DateTime? expiresAt;
  final int downloadCount;

  bool get isReady => status == 'ready';
}

abstract interface class PrivacyExportRepository {
  Future<PrivacyExport?> load();
  Future<PrivacyExport> request({
    required String accountPassword,
    required String exportPassword,
  });
  Future<void> download(String exportId);
}

class SupabasePrivacyExportRepository implements PrivacyExportRepository {
  const SupabasePrivacyExportRepository(
    this._client, {
    this.urlOpener = openSecureExportUrl,
  });

  final SupabaseClient _client;
  final Future<void> Function(Uri) urlOpener;

  @override
  Future<PrivacyExport?> load() async {
    final row = await _client
        .from('data_exports')
        .select('id,status,byte_size,expires_at,download_count,created_at')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : _decode(row);
  }

  @override
  Future<PrivacyExport> request({
    required String accountPassword,
    required String exportPassword,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const AuthException('Sign in again to export.');
    await _client.auth.signInWithPassword(
      email: email,
      password: accountPassword,
    );
    final result = await _client.functions.invoke(
      'privacy-export',
      body: {'action': 'request', 'password': exportPassword},
    );
    final body = result.data;
    if (result.status != 200 || body is! Map) {
      throw StateError('Export could not be prepared.');
    }
    final value = body['export'];
    if (value is! Map) throw const FormatException('Invalid export response');
    return _decode(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> download(String exportId) async {
    final result = await _client.functions.invoke(
      'privacy-export',
      body: {'action': 'download', 'export_id': exportId},
    );
    final body = result.data;
    final rawUrl = body is Map ? body['download_url'] : null;
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (result.status != 200 || url == null) {
      throw StateError('Secure download could not be opened.');
    }
    await urlOpener(url);
  }

  PrivacyExport _decode(Map<String, dynamic> value) {
    final id = value['id'];
    final status = value['status'];
    if (id is! String || status is! String) {
      throw const FormatException('Invalid export state');
    }
    final byteSize = value['byte_size'];
    final downloadCount = value['download_count'];
    return PrivacyExport(
      id: id,
      status: status,
      byteSize: byteSize is num ? byteSize.toInt() : null,
      expiresAt: DateTime.tryParse(value['expires_at'] as String? ?? ''),
      downloadCount: downloadCount is num ? downloadCount.toInt() : 0,
    );
  }
}

class FixturePrivacyExportRepository implements PrivacyExportRepository {
  const FixturePrivacyExportRepository();

  @override
  Future<PrivacyExport?> load() async => null;

  @override
  Future<PrivacyExport> request({
    required String accountPassword,
    required String exportPassword,
  }) async => const PrivacyExport(id: 'fixture', status: 'ready', byteSize: 42);

  @override
  Future<void> download(String exportId) async {}
}
