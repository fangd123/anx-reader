import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_system_preset.dart';
import 'package:flutter/material.dart';

Future<AiSystemPreset?> showAiSystemPresetPicker(
  BuildContext context, {
  required List<AiSystemPreset> presets,
  AiSystemPreset? selectedPreset,
}) {
  return showModalBottomSheet<AiSystemPreset>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: presets.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: Text(L10n.of(context).aiPresetSelect),
              );
            }

            final preset = presets[index - 1];
            return ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(preset.name),
              subtitle: Text(
                preset.systemPrompt.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: selectedPreset?.id == preset.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(preset),
            );
          },
        ),
      );
    },
  );
}
