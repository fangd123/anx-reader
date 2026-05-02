import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_preview.freezed.dart';
part 'sync_preview.g.dart';

@freezed
abstract class SyncPreviewGroup with _$SyncPreviewGroup {
  const factory SyncPreviewGroup({
    @Default(0) int local,
    @Default(0) int remote,
    @Default(0) int merged,
  }) = _SyncPreviewGroup;

  factory SyncPreviewGroup.fromJson(Map<String, dynamic> json) =>
      _$SyncPreviewGroupFromJson(json);
}

@freezed
abstract class SyncPreviewState with _$SyncPreviewState {
  const factory SyncPreviewState({
    required SyncPreviewGroup progress,
    required SyncPreviewGroup annotations,
    required SyncPreviewGroup chat,
    required SyncPreviewGroup config,
    required SyncPreviewGroup assets,
    @Default(<String>[]) List<String> warnings,
    @Default(false) bool hasRemoteData,
  }) = _SyncPreviewState;

  factory SyncPreviewState.fromJson(Map<String, dynamic> json) =>
      _$SyncPreviewStateFromJson(json);
}
