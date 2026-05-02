import 'package:freezed_annotation/freezed_annotation.dart';

part 'book_sync_state.freezed.dart';
part 'book_sync_state.g.dart';

@freezed
abstract class SyncProgressState with _$SyncProgressState {
  const factory SyncProgressState({
    @Default('') String position,
    @Default(0) double percentage,
    String? xpointer,
    String? fraction,
    String? deviceId,
    @Default('') String updatedAt,
  }) = _SyncProgressState;

  factory SyncProgressState.fromJson(Map<String, dynamic> json) =>
      _$SyncProgressStateFromJson(json);
}

@freezed
abstract class SyncAnnotationState with _$SyncAnnotationState {
  const factory SyncAnnotationState({
    required String key,
    required String type,
    @Default('') String cfi,
    @Default('') String content,
    @Default('') String chapter,
    @Default('') String color,
    String? readerNote,
    String? createdAt,
    @Default('') String updatedAt,
    @Default(false) bool deleted,
  }) = _SyncAnnotationState;

  factory SyncAnnotationState.fromJson(Map<String, dynamic> json) =>
      _$SyncAnnotationStateFromJson(json);
}

@freezed
abstract class BookAssetSyncState with _$BookAssetSyncState {
  const factory BookAssetSyncState({
    @Default(false) bool filesSyncEnabled,
    @Default(false) bool hasRemoteBook,
    @Default(false) bool hasRemoteCover,
    String? remoteBookPath,
    String? remoteCoverPath,
    String? localBookPath,
    String? localCoverPath,
    @Default('') String updatedAt,
  }) = _BookAssetSyncState;

  factory BookAssetSyncState.fromJson(Map<String, dynamic> json) =>
      _$BookAssetSyncStateFromJson(json);
}

@freezed
abstract class BookImportHints with _$BookImportHints {
  const factory BookImportHints({
    String? opdsSourceId,
    String? lastKnownFileName,
    String? title,
    String? author,
  }) = _BookImportHints;

  factory BookImportHints.fromJson(Map<String, dynamic> json) =>
      _$BookImportHintsFromJson(json);
}

@freezed
abstract class BookSyncState with _$BookSyncState {
  const factory BookSyncState({
    required String md5,
    @Default('') String title,
    @Default('') String author,
    @Default('') String fileExt,
    @Default('') String updatedAt,
    required SyncProgressState progress,
    @Default(<SyncAnnotationState>[]) List<SyncAnnotationState> annotations,
    @Default(<SyncAnnotationState>[]) List<SyncAnnotationState> bookmarks,
    required BookAssetSyncState assetState,
    required BookImportHints importHints,
  }) = _BookSyncState;

  factory BookSyncState.fromJson(Map<String, dynamic> json) =>
      _$BookSyncStateFromJson(json);
}

@freezed
abstract class SyncShadowState with _$SyncShadowState {
  const factory SyncShadowState({
    @Default('') String md5,
    String? lastSyncedAt,
    BookSyncState? state,
  }) = _SyncShadowState;

  factory SyncShadowState.fromJson(Map<String, dynamic> json) =>
      _$SyncShadowStateFromJson(json);
}

enum SyncConflictType {
  progress,
  annotation,
  bookmark,
  chat,
  config,
}

@freezed
abstract class SyncConflict with _$SyncConflict {
  const factory SyncConflict({
    required SyncConflictType type,
    required String scope,
    required String message,
    String? localUpdatedAt,
    String? remoteUpdatedAt,
  }) = _SyncConflict;

  factory SyncConflict.fromJson(Map<String, dynamic> json) =>
      _$SyncConflictFromJson(json);
}

@freezed
abstract class SyncAnnotationTombstone with _$SyncAnnotationTombstone {
  const factory SyncAnnotationTombstone({
    required String md5,
    required String key,
    required String type,
    @Default('') String cfi,
    @Default('') String deletedAt,
  }) = _SyncAnnotationTombstone;

  factory SyncAnnotationTombstone.fromJson(Map<String, dynamic> json) =>
      _$SyncAnnotationTombstoneFromJson(json);
}

@freezed
abstract class KOReaderProgressRecord with _$KOReaderProgressRecord {
  const factory KOReaderProgressRecord({
    required String md5,
    @Default(0) double percentage,
    String? xpointer,
    String? fraction,
    @Default('') String timestamp,
    String? device,
  }) = _KOReaderProgressRecord;

  factory KOReaderProgressRecord.fromJson(Map<String, dynamic> json) =>
      _$KOReaderProgressRecordFromJson(json);
}
