import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_system_preset.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_system_presets.g.dart';

@riverpod
class AiSystemPresets extends _$AiSystemPresets {
  @override
  List<AiSystemPreset> build() {
    final presets = Prefs().aiSystemPresets;
    presets.sort((a, b) => a.order.compareTo(b.order));
    return presets;
  }

  List<AiSystemPreset> getEnabledPresets() {
    return state.where((preset) => preset.enabled).toList(growable: false);
  }

  void addPreset({
    required String name,
    required String systemPrompt,
  }) {
    final now = DateTime.now();
    final newPreset = AiSystemPreset(
      id: now.microsecondsSinceEpoch.toString(),
      name: name,
      systemPrompt: systemPrompt,
      enabled: true,
      order: state.length,
      createdAt: now,
      updatedAt: now,
    );

    _saveAndUpdate([...state, newPreset]);
  }

  void updatePreset(AiSystemPreset preset) {
    final updated = state.map((item) {
      if (item.id == preset.id) {
        return preset.copyWith(updatedAt: DateTime.now());
      }
      return item;
    }).toList(growable: false);

    _saveAndUpdate(updated);
  }

  void deletePreset(String id) {
    final updated = state.where((preset) => preset.id != id).toList();
    for (int i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(order: i);
    }
    _saveAndUpdate(updated);
  }

  void toggleEnabled(String id) {
    final updated = state.map((preset) {
      if (preset.id == id) {
        return preset.copyWith(
          enabled: !preset.enabled,
          updatedAt: DateTime.now(),
        );
      }
      return preset;
    }).toList(growable: false);

    _saveAndUpdate(updated);
  }

  void movePreset(String id, bool moveUp) {
    final index = state.indexWhere((preset) => preset.id == id);
    if (index == -1) return;

    final newIndex = moveUp ? index - 1 : index + 1;
    if (newIndex < 0 || newIndex >= state.length) return;

    final updated = List<AiSystemPreset>.from(state);
    final temp = updated[index];
    updated[index] = updated[newIndex];
    updated[newIndex] = temp;

    for (int i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(
        order: i,
        updatedAt: DateTime.now(),
      );
    }

    _saveAndUpdate(updated);
  }

  void refresh() {
    ref.invalidateSelf();
  }

  void _saveAndUpdate(List<AiSystemPreset> presets) {
    Prefs().aiSystemPresets = presets;
    state = presets;
  }
}
