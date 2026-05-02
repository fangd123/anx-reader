import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('syncable config snapshot strips ai provider keys', () {
    Prefs().saveAiProviders([
      {
        'id': 'openai',
        'title': 'OpenAI',
        'url': 'https://api.openai.com/v1',
        'protocol': 'openai',
        'enabled': true,
        'isBuiltin': true,
        'apiKeys': [
          {'id': 'k1', 'key': 'secret', 'enabled': true}
        ],
        'model': 'gpt-4.1',
        'keyIndex': 0,
      }
    ]);

    final snapshot = Prefs().buildSyncableConfigSnapshot();
    final values = Map<String, dynamic>.from(snapshot['values'] as Map);
    final providers =
        (values['aiProviders'] as List).cast<Map<String, dynamic>>();
    final updatedAt = Map<String, dynamic>.from(snapshot['updatedAt'] as Map);

    expect(providers, hasLength(1));
    expect(providers.first['apiKeys'], isEmpty);
    expect(values['selectedAiService'], isA<String>());
    expect(updatedAt['aiProviders'], isA<String>());
  });

  test('apply syncable config snapshot keeps newer local key', () async {
    Prefs().selectedAiService = 'openai';
    final local = Prefs().buildSyncableConfigSnapshot();
    final localMeta = Map<String, dynamic>.from(local['updatedAt'] as Map);

    await Prefs().applySyncableConfigSnapshot({
      'values': {
        'selectedAiService': 'anthropic',
      },
      'updatedAt': {
        'selectedAiService': '2000-01-01T00:00:00.000Z',
      },
    });

    expect(Prefs().selectedAiService, 'openai');
    expect(localMeta['selectedAiService'], isA<String>());
  });
}
