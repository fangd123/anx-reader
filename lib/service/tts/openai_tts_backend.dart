import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class OpenAiTtsProvider extends TtsServiceProvider {
  static final OpenAiTtsProvider _instance =
      OpenAiTtsProvider._internal(http.Client());

  final http.Client _client;

  factory OpenAiTtsProvider() {
    return _instance;
  }

  OpenAiTtsProvider._internal(this._client);

  @visibleForTesting
  OpenAiTtsProvider.withClient(this._client);

  static const String _defaultUrl =
      'https://tts.wangwangit.com/v1/audio/speech';
  static const String _defaultVoice = 'zh-CN-XiaoxiaoNeural';
  static const double _minSpeed = 0.5;
  static const double _maxSpeed = 2.0;
  static const double _minPitch = -50.0;
  static const double _maxPitch = 50.0;

  @override
  TtsService get service => TtsService.openai;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateOpenAiTts;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: 'VoiceCraft OpenAI-compatible TTS',
        link: 'https://github.com/wangwangit/tts',
      ),
      ConfigItem(
        key: 'url',
        label: 'URL',
        description: L10n.of(context).settingsNarrateOpenAiUrlDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultUrl,
      ),
      ConfigItem(
        key: 'voice',
        label: 'Voice',
        description: L10n.of(context).settingsNarrateOpenAiVoiceDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultVoice,
      ),
      ConfigItem(
        key: 'pitch',
        label: 'Pitch',
        description: 'Optional (-50 to 50)',
        type: ConfigItemType.number,
        defaultValue: '',
        min: _minPitch,
        max: _maxPitch,
      ),
      ConfigItem(
        key: 'style',
        label: 'Style',
        description: 'Optional voice style',
        type: ConfigItemType.select,
        defaultValue: '',
        options: [
          {'label': L10n.of(context).commonNotSet, 'value': ''},
          {'label': 'General', 'value': 'general'},
          {'label': 'Assistant', 'value': 'assistant'},
          {'label': 'Chat', 'value': 'chat'},
          {'label': 'Customer service', 'value': 'customerservice'},
          {'label': 'Newscast', 'value': 'newscast'},
          {'label': 'Affectionate', 'value': 'affectionate'},
          {'label': 'Calm', 'value': 'calm'},
          {'label': 'Cheerful', 'value': 'cheerful'},
          {'label': 'Gentle', 'value': 'gentle'},
          {'label': 'Lyrical', 'value': 'lyrical'},
          {'label': 'Serious', 'value': 'serious'},
        ],
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    if (config.isEmpty) {
      return {
        'url': _defaultUrl,
        'voice': _defaultVoice,
        'pitch': '',
        'style': '',
      };
    }
    return {
      'url': config['url'] ?? _defaultUrl,
      'voice': config['voice'] ?? _defaultVoice,
      'pitch': config['pitch'] ?? '',
      'style': config['style'] ?? '',
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = getConfig();
    final String url = config['url']?.toString().trim() ?? _defaultUrl;
    final String resolvedVoice = resolveVoice(voice);
    final double speed = _normalizeSpeed(rate);
    final String? configuredPitch = _normalizePitch(config['pitch']);
    final String? style = _optionalString(config['style']);

    final response = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': text,
        'voice': resolvedVoice,
        'speed': speed,
        if (configuredPitch != null) 'pitch': configuredPitch,
        if (style != null) 'style': style,
      }),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    throw Exception(
        'OpenAI TTS failed: ${response.statusCode} ${response.body}');
  }

  double _normalizeSpeed(double rate) {
    if (!rate.isFinite) return 1.0;
    return rate.clamp(_minSpeed, _maxSpeed).toDouble();
  }

  String? _normalizePitch(dynamic value) {
    final raw = _optionalString(value);
    if (raw == null) return null;

    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) return null;

    final pitch = parsed.clamp(_minPitch, _maxPitch).toDouble();
    return pitch == pitch.roundToDouble()
        ? pitch.toInt().toString()
        : pitch.toString();
  }

  String? _optionalString(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    return const [
      TtsVoice(
          shortName: 'zh-CN-XiaoxiaoNeural',
          name: 'Xiaoxiao',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoyiNeural',
          name: 'Xiaoyi',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaochenNeural',
          name: 'Xiaochen',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaohanNeural',
          name: 'Xiaohan',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaomengNeural',
          name: 'Xiaomeng',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaomoNeural',
          name: 'Xiaomo',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoqiuNeural',
          name: 'Xiaoqiu',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoruiNeural',
          name: 'Xiaorui',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoshuangNeural',
          name: 'Xiaoshuang',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoxuanNeural',
          name: 'Xiaoxuan',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoyanNeural',
          name: 'Xiaoyan',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaoyouNeural',
          name: 'Xiaoyou',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-XiaozhenNeural',
          name: 'Xiaozhen',
          locale: 'zh-CN',
          gender: 'Female'),
      TtsVoice(
          shortName: 'zh-CN-YunxiNeural',
          name: 'Yunxi',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunyangNeural',
          name: 'Yunyang',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunjianNeural',
          name: 'Yunjian',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunfengNeural',
          name: 'Yunfeng',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunhaoNeural',
          name: 'Yunhao',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunxiaNeural',
          name: 'Yunxia',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunyeNeural',
          name: 'Yunye',
          locale: 'zh-CN',
          gender: 'Male'),
      TtsVoice(
          shortName: 'zh-CN-YunzeNeural',
          name: 'Yunze',
          locale: 'zh-CN',
          gender: 'Male'),
    ];
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final config = getConfig();
    final voice = config['voice']?.toString() ?? '';
    if (voice.isNotEmpty) return voice;
    return _defaultVoice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }
}
