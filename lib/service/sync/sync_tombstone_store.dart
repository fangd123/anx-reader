import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:anx_reader/service/sync/sync_json_file.dart';
import 'package:anx_reader/utils/get_path/sync_path.dart';

class SyncTombstoneStore {
  const SyncTombstoneStore._();

  static Future<Map<String, SyncAnnotationTombstone>> readAll() async {
    final file = await getAnxSyncTombstoneFile();
    final json = await SyncJsonFile.readMap(file);
    if (json == null) {
      return {};
    }
    return json.map((key, value) {
      if (value is Map<String, dynamic>) {
        return MapEntry(key, SyncAnnotationTombstone.fromJson(value));
      }
      if (value is Map) {
        return MapEntry(
          key,
          SyncAnnotationTombstone.fromJson(Map<String, dynamic>.from(value)),
        );
      }
      throw const FormatException('Invalid tombstone payload');
    });
  }

  static Future<void> markDeleted(
    SyncAnnotationTombstone tombstone,
  ) async {
    final all = await readAll();
    all[tombstone.key] = tombstone;
    final file = await getAnxSyncTombstoneFile();
    await SyncJsonFile.writeJson(
      file,
      all.map((key, value) => MapEntry(key, value.toJson())),
    );
  }

  static Future<void> remove(String key) async {
    final all = await readAll();
    if (all.remove(key) == null) {
      return;
    }
    final file = await getAnxSyncTombstoneFile();
    await SyncJsonFile.writeJson(
      file,
      all.map((entryKey, value) => MapEntry(entryKey, value.toJson())),
    );
  }
}
