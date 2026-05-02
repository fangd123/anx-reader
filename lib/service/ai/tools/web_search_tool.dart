import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/base_tool.dart';
import 'package:anx_reader/service/ai/tools/input/web_search_input.dart';
import 'package:anx_reader/service/ai/tools/repository/tavily_search_repository.dart';

const String webSearchToolId = 'web_search';

class WebSearchTool
    extends RepositoryTool<WebSearchInput, Map<String, dynamic>> {
  WebSearchTool(this._repository)
      : super(
          name: webSearchToolId,
          description:
              'Search the public internet for recent or external information using Tavily. Use this when the answer depends on current events, public web sources, or facts outside the user library. Prefer book-local tools for questions about the current book. Returns ranked sources with titles, URLs, snippets, optional answer synthesis, and metadata.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description':
                    'Required. The search query to send to Tavily. Be specific and include concrete names, dates, places, or quoted text when useful.',
              },
              'topic': {
                'type': 'string',
                'enum': ['general', 'news', 'finance'],
                'description':
                    'Optional. Search domain. Omit to use the app default.',
              },
              'searchDepth': {
                'type': 'string',
                'enum': ['basic', 'advanced', 'fast', 'ultra-fast'],
                'description':
                    'Optional. Search depth and latency/cost profile. Omit to use the app default.',
              },
              'maxResults': {
                'type': 'integer',
                'description':
                    'Optional. Number of results to return. Range 1-20.',
              },
              'timeRange': {
                'type': 'string',
                'enum': ['day', 'week', 'month', 'year', 'd', 'w', 'm', 'y'],
                'description': 'Optional. Restrict to recent results only.',
              },
              'includeDomains': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Optional. Only search within these domains.',
              },
              'excludeDomains': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Optional. Exclude these domains from the search.',
              },
              'includeAnswer': {
                'type': 'boolean',
                'description':
                    'Optional. Request Tavily to return a short synthesized answer in addition to search results.',
              },
              'includeRawContent': {
                'type': 'boolean',
                'description':
                    'Optional. Include truncated cleaned page content for deeper evidence gathering.',
              },
              'includeImages': {
                'type': 'boolean',
                'description':
                    'Optional. Include image URLs when visual results are relevant.',
              },
              'exactMatch': {
                'type': 'boolean',
                'description':
                    'Optional. When true, tighten matching to the exact query string where supported.',
              },
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 30),
        );

  final TavilySearchRepository _repository;

  @override
  WebSearchInput parseInput(Map<String, dynamic> json) {
    return WebSearchInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(WebSearchInput input) async {
    return _repository.search(input);
  }
}

final AiToolDefinition webSearchToolDefinition = AiToolDefinition(
  id: webSearchToolId,
  enabledByDefault: false,
  displayNameBuilder: (L10n l10n) => l10n.aiToolWebSearchName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolWebSearchDescription,
  isAvailable: (context) => context.tavilySearchRepository.hasValidConfig,
  build: (context) => WebSearchTool(context.tavilySearchRepository).tool,
);
