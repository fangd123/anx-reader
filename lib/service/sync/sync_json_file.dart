import 'dart:convert';
import 'dart:io';

class SyncJsonFile {
  const SyncJsonFile._();

  static Future<Map<String, dynamic>?> readMap(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
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
  }

  static Future<List<dynamic>> readList(File file) async {
    if (!await file.exists()) {
      return const [];
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(content);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    return const [];
  }

  static Future<void> writeJson(File file, Object value) async {
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(value));
  }
}
