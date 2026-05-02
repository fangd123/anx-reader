import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:path/path.dart' as p;

class WebdavObjectStore {
  WebdavObjectStore(this._client);

  static const String root = 'anx-sync/v2';

  final SyncClientBase _client;

  String manifestPath() => '$root/manifest.json';
  String devicePath(String deviceId) => '$root/devices/$deviceId.json';
  String bookStatePath(String md5) => '$root/books/$md5/state.json';
  String bookAssetPath(String md5, String extension) =>
      '$root/books/$md5/book.$extension';
  String coverAssetPath(String md5, String extension) =>
      '$root/books/$md5/cover.$extension';
  String aiSessionPath(String sessionId) => '$root/ai/sessions/$sessionId.json';
  String globalConfigPath() => '$root/config/global.json';

  Future<void> ensureRoot() async {
    await _client.mkdirAll('$root/books');
    await _client.mkdirAll('$root/devices');
    await _client.mkdirAll('$root/ai/sessions');
    await _client.mkdirAll('$root/config');
  }

  Future<bool> exists(String remotePath) => _client.isExist(remotePath);

  Future<Map<String, dynamic>?> readJson(String remotePath) async {
    final tempFile = await _createTempFile(remotePath);
    try {
      await _client.downloadFile(remotePath, tempFile.path);
      final content = await tempFile.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<List<dynamic>> readJsonList(String remotePath) async {
    final tempFile = await _createTempFile(remotePath);
    try {
      await _client.downloadFile(remotePath, tempFile.path);
      final content = await tempFile.readAsString();
      if (content.trim().isEmpty) {
        return const [];
      }
      final decoded = jsonDecode(content);
      if (decoded is List<dynamic>) {
        return decoded;
      }
      return const [];
    } catch (_) {
      return const [];
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> writeJson(String remotePath, Object value) async {
    final tempFile = await _createTempFile(remotePath);
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    try {
      await _client.mkdirAll(p.posix.dirname(remotePath));
      await _client.uploadFile(tempFile.path, remotePath, replace: true);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<List<String>> listBookMd5s() async {
    final files = await _client.safeReadDir('$root/books');
    return files
        .where((file) => file.isDir == true && (file.name?.isNotEmpty ?? false))
        .map((file) => file.name!)
        .toList(growable: false);
  }

  Future<List<String>> listDeviceIds() async {
    final files = await _client.safeReadDir('$root/devices');
    return files
        .where((file) => file.name?.endsWith('.json') ?? false)
        .map((file) => file.name!.replaceAll('.json', ''))
        .toList(growable: false);
  }

  Future<List<String>> listAiSessionIds() async {
    final files = await _client.safeReadDir('$root/ai/sessions');
    return files
        .where((file) => file.name?.endsWith('.json') ?? false)
        .map((file) => file.name!.replaceAll('.json', ''))
        .toList(growable: false);
  }

  Future<RemoteFile?> readProps(String remotePath) => _client.readProps(remotePath);

  Future<void> uploadAsset(String localPath, String remotePath) async {
    await _client.mkdirAll(p.posix.dirname(remotePath));
    await _client.uploadFile(localPath, remotePath, replace: true);
  }

  Future<void> downloadAsset(String remotePath, String localPath) async {
    final parent = Directory(p.dirname(localPath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await _client.downloadFile(remotePath, localPath);
  }

  Future<File> _createTempFile(String remotePath) async {
    final tempDir = await getAnxTempDir();
    final fileName = remotePath
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(':', '_');
    return File(
      '${tempDir.path}${Platform.pathSeparator}$fileName-${DateTime.now().microsecondsSinceEpoch}.json',
    );
  }
}
