import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await Prefs().saveOnlineTtsConfig('openai', {
      'url': 'https://tts.example.com/v1/audio/speech',
      'voice': 'zh-CN-XiaoxiaoNeural',
      'pitch': '',
      'style': '',
    });
  });

  test('sends speed in the supported OpenAI-compatible range', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final provider = OpenAiTtsProvider.withClient(MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response.bytes([1, 2, 3], 200);
    }));

    for (final rate in [0.0, 1.2, 3.0]) {
      await provider.speak('test', null, rate, 1.0);
    }

    expect(requestBodies.map((body) => body['speed']), [0.5, 1.2, 2.0]);
    expect(requestBodies, everyElement(hasLength(3)));
    expect(requestBodies, everyElement(isNot(contains('pitch'))));
    expect(requestBodies, everyElement(isNot(contains('style'))));
    expect(requestBodies, everyElement(isNot(contains('instructions'))));
  });

  test('sends non-empty pitch and style', () async {
    await Prefs().saveOnlineTtsConfig('openai', {
      'url': 'https://tts.example.com/v1/audio/speech',
      'voice': 'zh-CN-YunxiNeural',
      'pitch': -25,
      'style': 'newscast',
    });
    late http.Request capturedRequest;
    final provider = OpenAiTtsProvider.withClient(MockClient((request) async {
      capturedRequest = request;
      return http.Response.bytes([1, 2, 3], 200);
    }));

    await provider.speak('test', null, 1.0, 2.0);

    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body, {
      'input': 'test',
      'voice': 'zh-CN-YunxiNeural',
      'speed': 1.0,
      'pitch': '-25',
      'style': 'newscast',
    });
    expect(capturedRequest.headers, isNot(contains('authorization')));
  });

  test('clamps configured pitch to the supported range', () async {
    final pitches = <String>[];
    final provider = OpenAiTtsProvider.withClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      pitches.add(body['pitch'] as String);
      return http.Response.bytes([1], 200);
    }));

    for (final pitch in [-80, 80]) {
      await Prefs().saveOnlineTtsConfig('openai', {
        'url': 'https://tts.example.com/v1/audio/speech',
        'voice': 'zh-CN-XiaoxiaoNeural',
        'pitch': pitch,
        'style': '',
      });
      await provider.speak('test', null, 1.0, 1.0);
    }

    expect(pitches, ['-50', '50']);
  });
}
