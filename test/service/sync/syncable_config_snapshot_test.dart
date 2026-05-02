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
    expect(providers.first.containsKey('keyIndex'), isFalse);
    expect(providers.first.containsKey('updatedAt'), isFalse);
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

  test('apply syncable config snapshot keeps local api keys for ai providers',
      () async {
    Prefs().saveAiProviders([
      {
        'id': 'openai',
        'title': 'OpenAI',
        'url': 'https://api.openai.com/v1',
        'protocol': 'openai',
        'enabled': true,
        'isBuiltin': true,
        'apiKeys': [
          {'id': 'k1', 'key': 'secret-local', 'enabled': true}
        ],
        'model': 'gpt-4.1',
        'keyIndex': 3,
      }
    ]);

    await Prefs().applySyncableConfigSnapshot({
      'values': {
        'aiProviders': [
          {
            'id': 'openai',
            'title': 'OpenAI Remote',
            'url': 'https://example.com/v1',
            'protocol': 'openai',
            'enabled': true,
            'isBuiltin': true,
            'apiKeys': const [],
            'model': 'gpt-4.1-mini',
          }
        ],
      },
      'updatedAt': {
        'aiProviders': '2100-01-01T00:00:00.000Z',
      },
    });

    final providers =
        (Prefs().getAiProviders()).cast<Map<String, dynamic>>();
    expect(providers, hasLength(1));
    expect(providers.first['title'], 'OpenAI Remote');
    expect(providers.first['url'], 'https://example.com/v1');
    expect(providers.first['model'], 'gpt-4.1-mini');
    expect(providers.first['keyIndex'], 3);
    expect((providers.first['apiKeys'] as List), hasLength(1));
    expect(
      ((providers.first['apiKeys'] as List).first as Map)['key'],
      'secret-local',
    );
  });

  test('save ai providers does not touch sync meta for key-only changes', () {
    Prefs().saveAiProviders([
      {
        'id': 'openai',
        'title': 'OpenAI',
        'url': 'https://api.openai.com/v1',
        'protocol': 'openai',
        'enabled': true,
        'isBuiltin': true,
        'apiKeys': const [],
        'model': 'gpt-4.1',
        'keyIndex': 0,
      }
    ]);
    final firstMeta = Prefs().syncableConfigMeta['aiProviders'];

    Prefs().saveAiProviders([
      {
        'id': 'openai',
        'title': 'OpenAI',
        'url': 'https://api.openai.com/v1',
        'protocol': 'openai',
        'enabled': true,
        'isBuiltin': true,
        'apiKeys': [
          {'id': 'k1', 'key': 'secret-local', 'enabled': true}
        ],
        'model': 'gpt-4.1',
        'keyIndex': 7,
      }
    ]);

    expect(Prefs().syncableConfigMeta['aiProviders'], firstMeta);
  });
}
