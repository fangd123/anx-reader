import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tavily_search_config.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/input/web_search_input.dart';
import 'package:anx_reader/service/ai/tools/web_search_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('stores Tavily config in shared preferences', () {
    const config = TavilySearchConfig(
      apiKey: 'tvly-dev-key',
      baseUrl: 'https://api.tavily.com',
      topic: TavilySearchTopic.news,
      searchDepth: TavilySearchDepth.advanced,
      maxResults: 7,
      includeAnswer: true,
      includeRawContent: true,
      includeImages: false,
    );

    Prefs().tavilySearchConfig = config;

    final restored = Prefs().tavilySearchConfig;
    expect(restored.apiKey, config.apiKey);
    expect(restored.topic, TavilySearchTopic.news);
    expect(restored.searchDepth, TavilySearchDepth.advanced);
    expect(restored.maxResults, 7);
    expect(restored.includeAnswer, isTrue);
    expect(restored.includeRawContent, isTrue);
    expect(restored.includeImages, isFalse);
  });

  test('web search tool is opt-in and request input resolves defaults', () {
    expect(AiToolRegistry.defaultEnabledToolIds(),
        isNot(contains(webSearchToolId)));

    const defaults = TavilySearchConfig(
      apiKey: 'tvly-dev-key',
      topic: TavilySearchTopic.finance,
      searchDepth: TavilySearchDepth.fast,
      maxResults: 6,
      includeAnswer: true,
      includeRawContent: false,
      includeImages: true,
    );

    final input = WebSearchInput.fromJson({
      'query': '  latest earnings  ',
      'timeRange': 'week',
      'includeDomains': ['example.com', ''],
      'excludeDomains': ['spam.test'],
    });

    expect(input.normalizedQuery, 'latest earnings');
    expect(input.resolvedTopic(defaults), TavilySearchTopic.finance);
    expect(input.resolvedSearchDepth(defaults), TavilySearchDepth.fast);
    expect(input.resolvedMaxResults(defaults), 6);
    expect(input.resolvedIncludeAnswer(defaults), isTrue);
    expect(input.resolvedIncludeImages(defaults), isTrue);
    expect(input.resolvedTimeRange(), 'w');
    expect(input.includeDomains, ['example.com']);
    expect(input.excludeDomains, ['spam.test']);
  });
}
