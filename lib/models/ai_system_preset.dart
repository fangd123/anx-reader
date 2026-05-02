import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_system_preset.freezed.dart';
part 'ai_system_preset.g.dart';

@freezed
abstract class AiSystemPreset with _$AiSystemPreset {
  const AiSystemPreset._();

  const factory AiSystemPreset({
    required String id,
    required String name,
    required String systemPrompt,
    @Default(true) bool enabled,
    required int order,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _AiSystemPreset;

  factory AiSystemPreset.fromJson(Map<String, dynamic> json) =>
      _$AiSystemPresetFromJson(json);
}
