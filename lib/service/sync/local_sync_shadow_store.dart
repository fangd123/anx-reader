import 'dart:io';

import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:anx_reader/service/sync/sync_json_file.dart';
import 'package:anx_reader/utils/get_path/sync_path.dart';

class LocalSyncShadowStore {
  const LocalSyncShadowStore._();

  static Future<SyncShadowState?> read(String md5) async {
    final file = await _fileForMd5(md5);
    final json = await SyncJsonFile.readMap(file);
    if (json == null) {
      return null;
    }
    return SyncShadowState.fromJson(json);
  }

  static Future<void> write(SyncShadowState state) async {
    final file = await _fileForMd5(state.md5);
    await SyncJsonFile.writeJson(file, state.toJson());
  }

  static Future<void> remove(String md5) async {
    final file = await _fileForMd5(md5);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> _fileForMd5(String md5) async {
    final dir = await getAnxSyncShadowDir();
    return File('${dir.path}${Platform.pathSeparator}$md5.json');
  }
}
