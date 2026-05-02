import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

class KOReaderProgressBridge {
  KOReaderProgressBridge({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  bool get isConfigured =>
      Prefs().koReaderSyncEnabled && Prefs().hasKoReaderConfig;

  Future<bool> authorize() async {
    if (!isConfigured) {
      return false;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      _url('/users/auth'),
      options: Options(
        headers: _headers(),
        responseType: ResponseType.json,
      ),
    );
    return response.statusCode == 200;
  }

  Future<KOReaderProgressRecord?> fetchProgress(String md5) async {
    if (!isConfigured || md5.isEmpty) {
      return null;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      _url('/syncs/progress/$md5'),
      options: Options(
        headers: _headers(),
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    if (response.statusCode != 200 || data == null || data.isEmpty) {
      return null;
    }
    final progressValue = data['progress']?.toString();
    final xpointer = _extractXPointer(progressValue);
    final fraction = _extractFraction(progressValue);
    return KOReaderProgressRecord(
      md5: data['document']?.toString() ?? md5,
      percentage: _normalizePercentage(data['percentage']),
      xpointer: xpointer,
      fraction: fraction,
      timestamp: _toIsoTimestamp(data['timestamp']),
      device: data['device']?.toString(),
    );
  }

  Future<KOReaderProgressRecord?> pushProgress(
    BookSyncState state, {
    String? deviceName,
  }) async {
    if (!isConfigured || state.md5.isEmpty) {
      return null;
    }
    final progressString = _serializeProgress(state.progress);
    final response = await _dio.put<Map<String, dynamic>>(
      _url('/syncs/progress'),
      data: jsonEncode({
        'document': state.md5,
        'progress': progressString,
        'percentage': state.progress.percentage.clamp(0.0, 1.0),
        'device': deviceName ?? Prefs().syncDeviceId,
        'device_id': Prefs().syncDeviceId,
      }),
      options: Options(
        headers: {
          ..._headers(),
          'content-type': 'application/json',
        },
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode != 200) {
      return null;
    }
    final timestamp = response.data?['timestamp'];
    return KOReaderProgressRecord(
      md5: state.md5,
      percentage: state.progress.percentage.clamp(0.0, 1.0),
      xpointer: state.progress.xpointer,
      fraction: state.progress.fraction,
      timestamp: _toIsoTimestamp(timestamp),
      device: deviceName ?? Prefs().syncDeviceId,
    );
  }

  SyncProgressState mergeIntoProgress({
    required SyncProgressState base,
    required KOReaderProgressRecord remote,
  }) {
    final position = _resolvePosition(base.position, remote);
    return base.copyWith(
      position: position,
      percentage: remote.percentage,
      xpointer: remote.xpointer ?? base.xpointer,
      fraction: remote.fraction ?? base.fraction,
      updatedAt:
          remote.timestamp.isNotEmpty ? remote.timestamp : base.updatedAt,
      deviceId: remote.device ?? base.deviceId,
    );
  }

  String? resolveReaderPosition(SyncProgressState progress) {
    final position = progress.position.trim();
    if (position.isNotEmpty) {
      return position;
    }
    if (progress.xpointer != null && progress.xpointer!.trim().isNotEmpty) {
      return _normalizePointer(progress.xpointer!.trim());
    }
    return null;
  }

  String? resolveReaderFraction(SyncProgressState progress) {
    final fraction = progress.fraction?.trim();
    if (fraction == null || fraction.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(fraction);
    if (parsed == null) {
      return null;
    }
    return parsed.clamp(0.0, 1.0).toString();
  }

  String _url(String path) {
    final base = Prefs().koReaderServerUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base$path';
  }

  Map<String, dynamic> _headers() {
    final username = Prefs().koReaderUsername;
    final userKey =
        md5.convert(utf8.encode(Prefs().koReaderPassword)).toString();
    return {
      'accept': 'application/vnd.koreader.v1+json',
      'x-auth-user': username,
      'x-auth-key': userKey,
    };
  }

  double _normalizePercentage(dynamic value) {
    if (value is num) {
      return value.toDouble().clamp(0.0, 1.0);
    }
    return double.tryParse(value?.toString() ?? '')?.clamp(0.0, 1.0) ?? 0.0;
  }

  String _toIsoTimestamp(dynamic unixTimestamp) {
    final seconds = unixTimestamp is num
        ? unixTimestamp.toInt()
        : int.tryParse(unixTimestamp?.toString() ?? '');
    if (seconds == null || seconds <= 0) {
      return '';
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toIso8601String();
  }

  String _serializeProgress(SyncProgressState progress) {
    if (progress.xpointer != null && progress.xpointer!.trim().isNotEmpty) {
      return progress.xpointer!.trim();
    }
    final position = progress.position.trim();
    if (position.isNotEmpty) {
      return _normalizePointer(position);
    }
    final fraction = resolveReaderFraction(progress);
    if (fraction != null) {
      return 'fraction:$fraction';
    }
    return progress.percentage.toString();
  }

  String _resolvePosition(
      String currentPosition, KOReaderProgressRecord remote) {
    if (remote.xpointer != null && remote.xpointer!.trim().isNotEmpty) {
      return _normalizePointer(remote.xpointer!.trim());
    }
    final current = currentPosition.trim();
    if (current.isNotEmpty) {
      return current;
    }
    final fraction = remote.fraction?.trim();
    if (fraction != null && fraction.isNotEmpty) {
      return 'fraction:$fraction';
    }
    return '';
  }

  String? _extractXPointer(String? progress) {
    final value = progress?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (_looksLikeXPointer(value) || _looksLikeCfi(value)) {
      return _normalizePointer(value);
    }
    return null;
  }

  String? _extractFraction(String? progress) {
    final value = progress?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.startsWith('fraction:')) {
      return value.substring('fraction:'.length);
    }
    final asDouble = double.tryParse(value);
    if (asDouble != null && asDouble >= 0 && asDouble <= 1) {
      return asDouble.toString();
    }
    return null;
  }

  bool _looksLikeXPointer(String value) {
    return value.startsWith('/') ||
        value.startsWith('(/') ||
        value.startsWith('point(') ||
        value.contains('/body/');
  }

  bool _looksLikeCfi(String value) {
    return value.startsWith('epubcfi(') || value.startsWith('CFI:');
  }

  String _normalizePointer(String value) {
    if (value.startsWith('CFI:')) {
      return value.substring(4);
    }
    return value;
  }
}
