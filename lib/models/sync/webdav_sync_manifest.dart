import 'package:freezed_annotation/freezed_annotation.dart';

part 'webdav_sync_manifest.freezed.dart';
part 'webdav_sync_manifest.g.dart';

@freezed
abstract class WebdavSyncManifest with _$WebdavSyncManifest {
  const factory WebdavSyncManifest({
    @Default(2) int version,
    @Default('') String updatedAt,
    @Default(<String>[]) List<String> books,
    @Default(<String>[]) List<String> devices,
    @Default(<String>[]) List<String> chats,
  }) = _WebdavSyncManifest;

  factory WebdavSyncManifest.fromJson(Map<String, dynamic> json) =>
      _$WebdavSyncManifestFromJson(json);
}

@freezed
abstract class WebdavSyncDeviceRecord with _$WebdavSyncDeviceRecord {
  const factory WebdavSyncDeviceRecord({
    required String deviceId,
    @Default('') String deviceName,
    @Default('') String platform,
    @Default('') String updatedAt,
  }) = _WebdavSyncDeviceRecord;

  factory WebdavSyncDeviceRecord.fromJson(Map<String, dynamic> json) =>
      _$WebdavSyncDeviceRecordFromJson(json);
}

