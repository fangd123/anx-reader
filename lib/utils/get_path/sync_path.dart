import 'dart:io';

import 'package:anx_reader/utils/get_path/get_base_path.dart';

Future<Directory> getAnxSyncDir() async {
  final path = await getAnxDocumentsPath();
  final dir = Directory('$path${Platform.pathSeparator}sync');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

Future<Directory> getAnxAiSessionDir() async {
  final syncDir = await getAnxSyncDir();
  final dir = Directory('${syncDir.path}${Platform.pathSeparator}ai_sessions');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

Future<Directory> getAnxSyncShadowDir() async {
  final syncDir = await getAnxSyncDir();
  final dir = Directory('${syncDir.path}${Platform.pathSeparator}shadow');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

Future<File> getAnxSyncTombstoneFile() async {
  final syncDir = await getAnxSyncDir();
  return File('${syncDir.path}${Platform.pathSeparator}tombstones.json');
}

Future<File> getAnxSyncPreviewFile() async {
  final syncDir = await getAnxSyncDir();
  return File('${syncDir.path}${Platform.pathSeparator}preview.json');
}
