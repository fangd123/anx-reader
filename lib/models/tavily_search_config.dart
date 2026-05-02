enum TavilySearchTopic {
  general('general'),
  news('news'),
  finance('finance');

  const TavilySearchTopic(this.code);

  final String code;

  static TavilySearchTopic fromCode(String? code) {
    final normalized = code?.trim().toLowerCase();
    for (final value in values) {
      if (value.code == normalized) {
        return value;
      }
    }
    return TavilySearchTopic.general;
  }
}

enum TavilySearchDepth {
  basic('basic'),
  advanced('advanced'),
  fast('fast'),
  ultraFast('ultra-fast');

  const TavilySearchDepth(this.code);

  final String code;

  static TavilySearchDepth fromCode(String? code) {
    final normalized = code?.trim().toLowerCase().replaceAll('_', '-');
    for (final value in values) {
      if (value.code == normalized) {
        return value;
      }
    }
    return TavilySearchDepth.basic;
  }
}

class TavilySearchConfig {
  static const String defaultBaseUrl = 'https://api.tavily.com';

  const TavilySearchConfig({
    this.apiKey = '',
    this.baseUrl = defaultBaseUrl,
    this.topic = TavilySearchTopic.general,
    this.searchDepth = TavilySearchDepth.basic,
    this.maxResults = 5,
    this.includeAnswer = false,
    this.includeRawContent = false,
    this.includeImages = false,
  });

  final String apiKey;
  final String baseUrl;
  final TavilySearchTopic topic;
  final TavilySearchDepth searchDepth;
  final int maxResults;
  final bool includeAnswer;
  final bool includeRawContent;
  final bool includeImages;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  bool get isConfigured => hasApiKey;

  int get resolvedMaxResults => maxResults.clamp(1, 10);

  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return defaultBaseUrl;
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  Uri get searchUri => Uri.parse(normalizedBaseUrl).resolve('search');

  TavilySearchConfig copyWith({
    String? apiKey,
    String? baseUrl,
    TavilySearchTopic? topic,
    TavilySearchDepth? searchDepth,
    int? maxResults,
    bool? includeAnswer,
    bool? includeRawContent,
    bool? includeImages,
  }) {
    return TavilySearchConfig(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      topic: topic ?? this.topic,
      searchDepth: searchDepth ?? this.searchDepth,
      maxResults: maxResults ?? this.maxResults,
      includeAnswer: includeAnswer ?? this.includeAnswer,
      includeRawContent: includeRawContent ?? this.includeRawContent,
      includeImages: includeImages ?? this.includeImages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'topic': topic.code,
      'searchDepth': searchDepth.code,
      'maxResults': maxResults,
      'includeAnswer': includeAnswer,
      'includeRawContent': includeRawContent,
      'includeImages': includeImages,
    };
  }

  factory TavilySearchConfig.fromJson(Map<String, dynamic> json) {
    return TavilySearchConfig(
      apiKey: (json['apiKey'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? defaultBaseUrl).toString(),
      topic: TavilySearchTopic.fromCode(json['topic']?.toString()),
      searchDepth: TavilySearchDepth.fromCode(
        json['searchDepth']?.toString(),
      ),
      maxResults: _readInt(json['maxResults']) ?? 5,
      includeAnswer: _readBool(json['includeAnswer']) ?? false,
      includeRawContent: _readBool(json['includeRawContent']) ?? false,
      includeImages: _readBool(json['includeImages']) ?? false,
    );
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
}
