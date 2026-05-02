import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/edge/edge_ws_connector.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class EdgeTtsProvider extends TtsServiceProvider {
  static final EdgeTtsProvider _instance = EdgeTtsProvider._internal();

  factory EdgeTtsProvider() {
    return _instance;
  }

  EdgeTtsProvider._internal();

  static const String _trustedClientToken =
      '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _baseUrl =
      'speech.platform.bing.com/consumer/speech/synthesize/readaloud';
  static const String _voiceListUrl =
      'https://$_baseUrl/voices/list?trustedclienttoken=$_trustedClientToken';
  static const String _wsUrl =
      'wss://$_baseUrl/edge/v1?TrustedClientToken=$_trustedClientToken';
  static const String _defaultVoice = 'en-US-EmmaMultilingualNeural';
  static const String _chromiumFullVersion = '143.0.3650.75';
  static const String _origin =
      'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';
  static const int _maxChunkBytes = 3800;
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 30);
  static const HtmlEscape _xmlEscape = HtmlEscape(HtmlEscapeMode.element);
  static final Uuid _uuid = const Uuid();
  static final Random _random = Random.secure();

  Duration _clockSkew = Duration.zero;

  @override
  TtsService get service => TtsService.edge;

  @override
  String getLabel(BuildContext context) => L10n.of(context).settingsNarrateEdgeTts;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue:
            'Edge Read Aloud provides free neural voices. No API key is required.',
      ),
    ];
  }

  @override
  Future<Uint8List> speak(
    String text,
    String? voice,
    double rate,
    double pitch,
  ) async {
    final resolvedVoice = _normalizeVoiceName(resolveVoice(voice));
    final sanitizedText = _sanitizeText(text);
    final escapedChunks =
        _splitEscapedText(_xmlEscape.convert(sanitizedText), _maxChunkBytes);

    final audio = BytesBuilder(copy: false);
    for (final chunk in escapedChunks) {
      final chunkAudio = await _synthesizeChunk(
        chunk,
        resolvedVoice,
        rate,
        pitch,
      );
      if (chunkAudio.isNotEmpty) {
        audio.add(chunkAudio);
      }
    }

    return audio.toBytes();
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    Future<http.Response> request() {
      final url = Uri.parse(_withSecurityParams(_voiceListUrl));
      return http.get(url, headers: _voiceHeaders()).timeout(_receiveTimeout);
    }

    var response = await request();
    if (response.statusCode == 403) {
      _updateClockSkewFromDate(response.headers['date']);
      response = await request();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Edge TTS voice list failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! List) {
      throw Exception('Edge TTS returned an invalid voice list.');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(convertVoiceModel)
        .toList()
      ..sort((a, b) {
        final localeCompare = a.locale.compareTo(b.locale);
        if (localeCompare != 0) {
          return localeCompare;
        }
        return a.name.compareTo(b.name);
      });
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) {
      return voiceData;
    }
    if (voiceData is! Map) {
      return const TtsVoice(shortName: '', name: '', locale: '');
    }

    final map = Map<String, dynamic>.from(voiceData);
    final voiceTag = map['VoiceTag'];
    final descriptionParts = <String>[];
    if (voiceTag is Map<String, dynamic>) {
      final categories = voiceTag['ContentCategories'];
      final personalities = voiceTag['VoicePersonalities'];
      if (categories is List) {
        descriptionParts.addAll(
          categories.map((e) => e.toString()).where((e) => e.isNotEmpty),
        );
      }
      if (personalities is List) {
        descriptionParts.addAll(
          personalities.map((e) => e.toString()).where((e) => e.isNotEmpty),
        );
      }
    }

    return TtsVoice(
      shortName: map['ShortName']?.toString() ?? '',
      name: map['FriendlyName']?.toString() ??
          map['LocalName']?.toString() ??
          map['ShortName']?.toString() ??
          '',
      locale: map['Locale']?.toString() ?? '',
      gender: map['Gender']?.toString() ?? '',
      description: descriptionParts.join(' · '),
      rawData: map,
    );
  }

  @override
  String getSelectedVoice() {
    final selected = Prefs().getTtsVoiceModel(serviceId);
    if (selected.isNotEmpty) {
      return selected;
    }
    return _defaultVoice;
  }

  @override
  void setSelectedVoice(String voice) {
    Prefs().setTtsVoiceModel(serviceId, voice);
  }

  Future<Uint8List> _synthesizeChunk(
    String escapedText,
    String voice,
    double rate,
    double pitch,
  ) async {
    final connection = await openEdgeWsConnection(
      Uri.parse(_buildWsUrl()),
      _wsHeaders(),
      connectTimeout: _connectTimeout,
    );

    final audio = BytesBuilder(copy: false);
    var receivedAudio = false;

    try {
      await connection.sendText(_buildSpeechConfigFrame());
      await connection.sendText(
        _buildSsmlFrame(
          escapedText: escapedText,
          voice: voice,
          rate: rate,
          pitch: pitch,
        ),
      );

      await for (final message in connection.messages.timeout(_receiveTimeout)) {
        if (message is String) {
          final headers = _parseTextFrameHeaders(message);
          if (headers['Path'] == 'turn.end') {
            break;
          }
          continue;
        }

        if (message is Uint8List) {
          final payload = _extractAudioPayload(message);
          if (payload != null && payload.isNotEmpty) {
            audio.add(payload);
            receivedAudio = true;
          }
        }
      }
    } finally {
      await connection.close();
    }

    if (!receivedAudio) {
      throw Exception('Edge TTS returned no audio.');
    }

    return audio.toBytes();
  }

  Uint8List? _extractAudioPayload(Uint8List frame) {
    if (frame.length < 2) {
      return null;
    }

    final headerLength = (frame[0] << 8) | frame[1];
    final dataStart = 2 + headerLength;
    if (dataStart > frame.length) {
      throw Exception('Edge TTS returned an invalid audio frame.');
    }

    final headers = _parseHeaderLines(
      utf8
          .decode(frame.sublist(2, dataStart), allowMalformed: true)
          .split('\r\n'),
    );
    if (headers['Path'] != 'audio') {
      return null;
    }

    final contentType = headers['Content-Type'];
    final payload = frame.sublist(dataStart);
    if (contentType == null) {
      return payload.isEmpty ? null : payload;
    }
    if (contentType != 'audio/mpeg') {
      throw Exception('Edge TTS returned unexpected content type: $contentType');
    }
    return payload;
  }

  Map<String, String> _parseTextFrameHeaders(String frame) {
    final separatorIndex = frame.indexOf('\r\n\r\n');
    if (separatorIndex == -1) {
      return {};
    }
    return _parseHeaderLines(
      frame.substring(0, separatorIndex).split('\r\n'),
    );
  }

  Map<String, String> _parseHeaderLines(List<String> lines) {
    final headers = <String, String>{};
    for (final line in lines) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      headers[line.substring(0, separator).trim()] =
          line.substring(separator + 1).trim();
    }
    return headers;
  }

  String _buildSpeechConfigFrame() {
    return 'X-Timestamp:${_edgeDate()}\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n';
  }

  String _buildSsmlFrame({
    required String escapedText,
    required String voice,
    required double rate,
    required double pitch,
  }) {
    return 'X-RequestId:${_requestId()}\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:${_edgeDate()}Z\r\n'
        'Path:ssml\r\n\r\n'
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'><voice name='$voice'><prosody "
        "pitch='${_pitchValue(pitch)}' rate='${_rateValue(rate)}' "
        "volume='+0%'>$escapedText</prosody></voice></speak>";
  }

  List<String> _splitEscapedText(String text, int maxBytes) {
    final chunks = <String>[];
    var remaining = text.trim();

    while (utf8.encode(remaining).length > maxBytes) {
      var currentOffset = 0;
      var currentBytes = 0;
      var lastWhitespaceOffset = -1;

      for (final rune in remaining.runes) {
        final char = String.fromCharCode(rune);
        final nextBytes = utf8.encode(char).length;
        if (currentBytes + nextBytes > maxBytes) {
          break;
        }
        currentBytes += nextBytes;
        currentOffset += char.length;
        if (RegExp(r'\s').hasMatch(char)) {
          lastWhitespaceOffset = currentOffset;
        }
      }

      var splitAt = lastWhitespaceOffset > 0 ? lastWhitespaceOffset : currentOffset;
      if (splitAt <= 0) {
        throw Exception('Edge TTS could not split the input text safely.');
      }

      final lastAmp = remaining.lastIndexOf('&', splitAt - 1);
      if (lastAmp >= 0) {
        final lastSemi = remaining.lastIndexOf(';', splitAt - 1);
        if (lastSemi < lastAmp) {
          splitAt = lastAmp;
        }
      }

      if (splitAt <= 0) {
        splitAt = currentOffset;
      }

      final chunk = remaining.substring(0, splitAt).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
      remaining = remaining.substring(splitAt).trimLeft();
    }

    if (remaining.isNotEmpty) {
      chunks.add(remaining);
    }

    return chunks;
  }

  String _sanitizeText(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if ((rune >= 0 && rune <= 8) ||
          (rune >= 11 && rune <= 12) ||
          (rune >= 14 && rune <= 31)) {
        buffer.write(' ');
      } else {
        buffer.write(String.fromCharCode(rune));
      }
    }
    return buffer.toString();
  }

  String _buildWsUrl() {
    return '$_wsUrl&ConnectionId=${_requestId()}'
        '&Sec-MS-GEC=${_generateSecMsGec()}'
        '&Sec-MS-GEC-Version=${_secMsGecVersion()}';
  }

  String _withSecurityParams(String url) {
    return '$url&Sec-MS-GEC=${_generateSecMsGec()}'
        '&Sec-MS-GEC-Version=${_secMsGecVersion()}';
  }

  Map<String, String> _voiceHeaders() {
    return {
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cookie': 'muid=${_generateMuid()};',
      'Sec-CH-UA':
          '" Not;A Brand";v="99", "Microsoft Edge";v="${_chromiumMajorVersion()}", '
          '"Chromium";v="${_chromiumMajorVersion()}"',
      'Sec-CH-UA-Mobile': '?0',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'none',
      'User-Agent': _userAgent(),
    };
  }

  Map<String, String> _wsHeaders() {
    return {
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Cookie': 'muid=${_generateMuid()};',
      'Origin': _origin,
      'Pragma': 'no-cache',
      'User-Agent': _userAgent(),
    };
  }

  void _updateClockSkewFromDate(String? serverDate) {
    if (serverDate == null || serverDate.isEmpty) {
      return;
    }
    final parsed = DateFormat(
      "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
      'en_US',
    ).parseUtc(serverDate);
    _clockSkew = parsed.difference(DateTime.now().toUtc());
  }

  String _generateSecMsGec() {
    final unixSeconds =
        DateTime.now().toUtc().add(_clockSkew).millisecondsSinceEpoch / 1000.0;
    var windowsSeconds = unixSeconds + 11644473600;
    windowsSeconds -= windowsSeconds % 300;
    final ticks = (windowsSeconds * 10000000).round();
    final input = '$ticks$_trustedClientToken';
    return sha256.convert(ascii.encode(input)).toString().toUpperCase();
  }

  String _generateMuid() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  String _requestId() {
    return _uuid.v4().replaceAll('-', '');
  }

  String _edgeDate() {
    return DateFormat(
      "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
      'en_US',
    ).format(DateTime.now().toUtc())
        .replaceFirst('GMT', 'GMT+0000 (Coordinated Universal Time)');
  }

  String _normalizeVoiceName(String voice) {
    final fullPattern = RegExp(
      r'^Microsoft Server Speech Text to Speech Voice \(.+,.+\)$',
    );
    if (fullPattern.hasMatch(voice)) {
      return voice;
    }

    final shortPattern = RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$');
    final match = shortPattern.firstMatch(voice);
    if (match == null) {
      return voice;
    }

    final language = match.group(1)!;
    var region = match.group(2)!;
    var name = match.group(3)!;
    final dashIndex = name.indexOf('-');
    if (dashIndex != -1) {
      region = '$region-${name.substring(0, dashIndex)}';
      name = name.substring(dashIndex + 1);
    }

    return 'Microsoft Server Speech Text to Speech Voice '
        '($language-$region, $name)';
  }

  String _rateValue(double rate) {
    final percent = (((rate - 1.0) * 100).round()).clamp(-100, 100);
    return '${percent >= 0 ? '+' : ''}$percent%';
  }

  String _pitchValue(double pitch) {
    final hz = (((pitch - 1.0) * 100).round()).clamp(-100, 100);
    return '${hz >= 0 ? '+' : ''}${hz}Hz';
  }

  String _chromiumMajorVersion() {
    return _chromiumFullVersion.split('.').first;
  }

  String _secMsGecVersion() {
    return '1-$_chromiumFullVersion';
  }

  String _userAgent() {
    final major = _chromiumMajorVersion();
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36 '
        'Edg/$major.0.0.0';
  }
}
