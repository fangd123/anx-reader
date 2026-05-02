import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tavily_search_config.dart';
import 'package:anx_reader/service/ai/tools/input/web_search_input.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

class TavilySearchRepository {
  TavilySearchRepository({
    TavilySearchConfig? config,
    http.Client? client,
  })  : _config = config,
        _client = client ?? http.Client();

  final TavilySearchConfig? _config;
  final http.Client _client;

  bool get hasValidConfig => effectiveConfig.isConfigured;

  TavilySearchConfig get effectiveConfig =>
      _config ?? Prefs().tavilySearchConfig;

  Future<Map<String, dynamic>> search(WebSearchInput input) async {
    final query = input.normalizedQuery;
    if (query.isEmpty) {
      throw ArgumentError('query must not be empty');
    }

    final config = effectiveConfig;
    if (!config.isConfigured) {
      throw StateError(
        'Tavily API key is not configured. Open AI settings and add a Tavily key first.',
      );
    }

    final requestBody = <String, dynamic>{
      'query': query,
      'topic': input.resolvedTopic(config).code,
      'search_depth': input.resolvedSearchDepth(config).code,
      'max_results': input.resolvedMaxResults(config),
      'include_answer': input.resolvedIncludeAnswer(config),
      'include_raw_content':
          input.resolvedIncludeRawContent(config) ? 'markdown' : false,
      'include_images': input.resolvedIncludeImages(config),
      'include_favicon': true,
      'include_usage': true,
      'include_domains': input.includeDomains,
      'exclude_domains': input.excludeDomains,
      'include_image_descriptions': input.resolvedIncludeImages(config),
      'exact_match': input.resolvedExactMatch(),
    };

    final timeRange = input.resolvedTimeRange();
    if (timeRange != null) {
      requestBody['time_range'] = timeRange;
    }

    AnxLog.info(
      'TavilySearchRepository: searching web query="$query" '
      'topic=${requestBody['topic']} depth=${requestBody['search_depth']} '
      'maxResults=${requestBody['max_results']}',
    );

    final response = await _client
        .post(
          config.searchUri,
          headers: <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer ${config.apiKey.trim()}',
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.acceptHeader: 'application/json',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 25));

    final payload = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractErrorMessage(payload) ??
            'Tavily request failed with status ${response.statusCode}',
        uri: config.searchUri,
      );
    }

    if (payload is! Map) {
      throw const FormatException('Unexpected Tavily response payload');
    }

    return _normalizeResponse(
      Map<String, dynamic>.from(payload),
      query: query,
      requestBody: requestBody,
    );
  }

  Future<Map<String, dynamic>> testConnection() async {
    final result = await search(
      const WebSearchInput(
        query: 'Tavily search API',
        maxResults: 1,
        includeAnswer: false,
        includeImages: false,
        includeRawContent: false,
      ),
    );

    return {
      'status': 'ok',
      'resultCount': result['resultCount'] ?? 0,
      'query': result['query'],
    };
  }

  Map<String, dynamic> _normalizeResponse(
    Map<String, dynamic> payload, {
    required String query,
    required Map<String, dynamic> requestBody,
  }) {
    final rawResults = payload['results'];
    final results = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .map(_normalizeResult)
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    final normalized = <String, dynamic>{
      'query': _stringValue(payload['query']) ?? query,
      'topic': requestBody['topic'],
      'searchDepth': requestBody['search_depth'],
      'maxResults': requestBody['max_results'],
      'resultCount': results.length,
      'results': results,
    };

    final answer = _truncate(_stringValue(payload['answer']), 2400);
    if (answer != null) {
      normalized['answer'] = answer;
    }

    final responseTime = payload['response_time'];
    if (responseTime is num) {
      normalized['responseTimeSeconds'] = responseTime.toDouble();
    }

    final requestId = _stringValue(payload['request_id']);
    if (requestId != null) {
      normalized['requestId'] = requestId;
    }

    final autoParameters = payload['auto_parameters'];
    if (autoParameters is Map) {
      normalized['autoParameters'] = Map<String, dynamic>.from(autoParameters);
    }

    final usage = payload['usage'];
    if (usage is Map) {
      normalized['usage'] = Map<String, dynamic>.from(usage);
    }

    final images = payload['images'];
    if (images is List) {
      final normalizedImages = images
          .map(_stringValue)
          .whereType<String>()
          .take(5)
          .toList(growable: false);
      if (normalizedImages.isNotEmpty) {
        normalized['images'] = normalizedImages;
      }
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeResult(Map<String, dynamic> item) {
    final normalized = <String, dynamic>{};

    final title = _truncate(_stringValue(item['title']), 300);
    if (title != null) {
      normalized['title'] = title;
    }

    final url = _stringValue(item['url']);
    if (url != null) {
      normalized['url'] = url;
    }

    final content = _truncate(_stringValue(item['content']), 1800);
    if (content != null) {
      normalized['content'] = content;
    }

    final rawContent = _truncate(_stringValue(item['raw_content']), 4000);
    if (rawContent != null) {
      normalized['rawContent'] = rawContent;
    }

    final favicon = _stringValue(item['favicon']);
    if (favicon != null) {
      normalized['favicon'] = favicon;
    }

    final publishedDate = _stringValue(item['published_date']);
    if (publishedDate != null) {
      normalized['publishedDate'] = publishedDate;
    }

    final score = item['score'];
    if (score is num) {
      normalized['score'] = score.toDouble();
    }

    return normalized;
  }

  dynamic _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return jsonDecode(body);
  }

  String? _extractErrorMessage(dynamic payload) {
    if (payload is Map) {
      final detail = payload['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }

  String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  String? _truncate(String? value, int maxLength) {
    if (value == null) {
      return null;
    }
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}
