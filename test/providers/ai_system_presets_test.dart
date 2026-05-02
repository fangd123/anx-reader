import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_system_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('stores, updates, toggles, reorders, and deletes system presets', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiSystemPresetsProvider.notifier);

    notifier.addPreset(name: 'Source Lookup', systemPrompt: 'Find sources');
    notifier.addPreset(name: 'History', systemPrompt: 'Explain background');

    expect(container.read(aiSystemPresetsProvider), hasLength(2));
    expect(Prefs().aiSystemPresets.map((preset) => preset.name).toList(),
        ['Source Lookup', 'History']);

    final first = container.read(aiSystemPresetsProvider).first;
    notifier.toggleEnabled(first.id);

    expect(
      container
          .read(aiSystemPresetsProvider)
          .firstWhere((preset) => preset.id == first.id)
          .enabled,
      isFalse,
    );

    final second = container.read(aiSystemPresetsProvider)[1];
    notifier.updatePreset(
      second.copyWith(
        name: 'Historical Context',
        systemPrompt: 'Explain the historical context',
      ),
    );

    expect(
      container.read(aiSystemPresetsProvider)[1].name,
      'Historical Context',
    );

    notifier.movePreset(second.id, true);
    expect(
      container.read(aiSystemPresetsProvider).map((preset) => preset.name),
      ['Historical Context', 'Source Lookup'],
    );
    expect(
      container.read(aiSystemPresetsProvider).map((preset) => preset.order),
      [0, 1],
    );

    notifier.deletePreset(first.id);
    expect(container.read(aiSystemPresetsProvider), hasLength(1));
    expect(container.read(aiSystemPresetsProvider).single.name,
        'Historical Context');
    expect(Prefs().aiSystemPresets.single.order, 0);
  });

  test('returns only enabled presets from provider helper', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiSystemPresetsProvider.notifier);
    notifier.addPreset(name: 'Enabled', systemPrompt: 'A');
    notifier.addPreset(name: 'Disabled', systemPrompt: 'B');

    final disabledId = container.read(aiSystemPresetsProvider)[1].id;
    notifier.toggleEnabled(disabledId);

    expect(
      notifier.getEnabledPresets().map((preset) => preset.name).toList(),
      ['Enabled'],
    );
  });
}
