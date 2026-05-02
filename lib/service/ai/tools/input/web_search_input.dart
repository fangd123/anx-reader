import 'package:anx_reader/models/tavily_search_config.dart';

class WebSearchInput {
  const WebSearchInput({
    required this.query,
    this.topic,
    this.searchDepth,
    this.maxResults,
    this.includeDomains = const <String>[],
    this.excludeDomains = const <String>[],
    this.timeRange,
    this.includeAnswer,
    this.includeRawContent,
    this.includeImages,
    this.exactMatch,
  });

  final String query;
  final String? topic;
  final String? searchDepth;
  final int? maxResults;
  final List<String> includeDomains;
  final List<String> excludeDomains;
  final String? timeRange;
  final bool? includeAnswer;
  final bool? includeRawContent;
  final bool? includeImages;
  final bool? exactMatch;

  factory WebSearchInput.fromJson(Map<String, dynamic> json) {
    return WebSearchInput(
      query: (json['query'] ?? '').toString(),
      topic: _readString(json['topic']),
      searchDepth: _readString(json['searchDepth']),
      maxResults: _readInt(json['maxResults']),
      includeDomains: _readStringList(json['includeDomains']),
      excludeDomains: _readStringList(json['excludeDomains']),
      timeRange: _readString(json['timeRange']),
      includeAnswer: _readBool(json['includeAnswer']),
      includeRawContent: _readBool(json['includeRawContent']),
      includeImages: _readBool(json['includeImages']),
      exactMatch: _readBool(json['exactMatch']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      if (topic != null) 'topic': topic,
      if (searchDepth != null) 'searchDepth': searchDepth,
      if (maxResults != null) 'maxResults': maxResults,
      if (includeDomains.isNotEmpty) 'includeDomains': includeDomains,
      if (excludeDomains.isNotEmpty) 'excludeDomains': excludeDomains,
      if (timeRange != null) 'timeRange': timeRange,
      if (includeAnswer != null) 'includeAnswer': includeAnswer,
      if (includeRawContent != null) 'includeRawContent': includeRawContent,
      if (includeImages != null) 'includeImages': includeImages,
      if (exactMatch != null) 'exactMatch': exactMatch,
    };
  }

  String get normalizedQuery => query.trim();

  TavilySearchTopic resolvedTopic(TavilySearchConfig defaults) {
    if (!_hasText(topic)) {
      return defaults.topic;
    }
    return TavilySearchTopic.fromCode(topic);
  }

  TavilySearchDepth resolvedSearchDepth(TavilySearchConfig defaults) {
    if (!_hasText(searchDepth)) {
      return defaults.searchDepth;
    }
    return TavilySearchDepth.fromCode(searchDepth);
  }

  int resolvedMaxResults(TavilySearchConfig defaults, {int max = 20}) {
    final value = maxResults ?? defaults.resolvedMaxResults;
    return value.clamp(1, max);
  }

  bool resolvedIncludeAnswer(TavilySearchConfig defaults) {
    return includeAnswer ?? defaults.includeAnswer;
  }

  bool resolvedIncludeRawContent(TavilySearchConfig defaults) {
    return includeRawContent ?? defaults.includeRawContent;
  }

  bool resolvedIncludeImages(TavilySearchConfig defaults) {
    return includeImages ?? defaults.includeImages;
  }

  bool resolvedExactMatch() => exactMatch ?? false;

  String? resolvedTimeRange() {
    final normalized = timeRange?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    switch (normalized) {
      case 'd':
      case 'day':
        return 'd';
      case 'w':
      case 'week':
        return 'w';
      case 'm':
      case 'month':
        return 'm';
      case 'y':
      case 'year':
        return 'y';
      default:
        return null;
    }
  }

  static String? _readString(Object? value) {
    final string = value?.toString().trim();
    if (string == null || string.isEmpty) {
      return null;
    }
    return string;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool? _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return null;
  }

  static List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
