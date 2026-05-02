import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/tavily_search_config.dart';
import 'package:anx_reader/service/ai/tools/repository/tavily_search_repository.dart';
import 'package:anx_reader/service/ai/tools/web_search_tool.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';

class AiWebSearchSettingsPage extends StatefulWidget {
  const AiWebSearchSettingsPage({super.key});

  @override
  State<AiWebSearchSettingsPage> createState() =>
      _AiWebSearchSettingsPageState();
}

class _AiWebSearchSettingsPageState extends State<AiWebSearchSettingsPage> {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;

  late TavilySearchTopic _topic;
  late TavilySearchDepth _searchDepth;
  late int _maxResults;
  late bool _includeAnswer;
  late bool _includeRawContent;
  late bool _includeImages;
  late bool _toolEnabled;

  bool _apiKeyVisible = false;
  bool _isModified = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = Prefs().tavilySearchConfig;
    _apiKeyController = TextEditingController(text: config.apiKey);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _topic = config.topic;
    _searchDepth = config.searchDepth;
    _maxResults = config.resolvedMaxResults;
    _includeAnswer = config.includeAnswer;
    _includeRawContent = config.includeRawContent;
    _includeImages = config.includeImages;
    _toolEnabled = Prefs().isAiToolEnabled(webSearchToolId);

    _apiKeyController.addListener(_markModified);
    _baseUrlController.addListener(_markModified);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final draftConfig = _buildDraftConfig();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiWebSearch),
        actions: [
          if (_isModified)
            TextButton(
              onPressed: _save,
              child: Text(l10n.commonSave),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsAiWebSearchHint,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(
                          draftConfig.isConfigured
                              ? Icons.check_circle_outline
                              : Icons.key_off_outlined,
                          size: 18,
                        ),
                        label: Text(
                          draftConfig.isConfigured
                              ? l10n.settingsAiWebSearchStatusConfigured
                              : l10n.settingsAiWebSearchStatusMissingKey,
                        ),
                      ),
                      Chip(
                        avatar: Icon(
                          _toolEnabled ? Icons.link : Icons.link_off,
                          size: 18,
                        ),
                        label: Text(
                          _toolEnabled
                              ? l10n.settingsAiWebSearchStatusToolEnabled
                              : l10n.settingsAiWebSearchStatusToolDisabled,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _toolEnabled,
              title: Text(l10n.settingsAiWebSearchToolEnabled),
              subtitle: Text(l10n.settingsAiWebSearchToolEnabledDescription),
              onChanged: (value) {
                setState(() {
                  _toolEnabled = value;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: !_apiKeyVisible,
              decoration: InputDecoration(
                labelText: l10n.settingsAiWebSearchApiKey,
                border: const OutlineInputBorder(),
                helperText: l10n.settingsAiWebSearchApiKeyDescription,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _apiKeyVisible = !_apiKeyVisible;
                    });
                  },
                  icon: Icon(
                    _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: InputDecoration(
                labelText: l10n.settingsAiWebSearchBaseUrl,
                border: const OutlineInputBorder(),
                helperText: l10n.settingsAiWebSearchBaseUrlDescription,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.settingsAiWebSearchDefaults,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TavilySearchTopic>(
              initialValue: _topic,
              decoration: InputDecoration(
                labelText: l10n.settingsAiWebSearchDefaultTopic,
                border: const OutlineInputBorder(),
              ),
              items: TavilySearchTopic.values
                  .map(
                    (topic) => DropdownMenuItem<TavilySearchTopic>(
                      value: topic,
                      child: Text(_topicLabel(l10n, topic)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _topic = value;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TavilySearchDepth>(
              initialValue: _searchDepth,
              decoration: InputDecoration(
                labelText: l10n.settingsAiWebSearchDefaultDepth,
                border: const OutlineInputBorder(),
              ),
              items: TavilySearchDepth.values
                  .map(
                    (depth) => DropdownMenuItem<TavilySearchDepth>(
                      value: depth,
                      child: Text(_depthLabel(l10n, depth)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _searchDepth = value;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsAiWebSearchDefaultMaxResults),
              subtitle: Slider(
                value: _maxResults.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: _maxResults.toString(),
                onChanged: (value) {
                  setState(() {
                    _maxResults = value.round();
                    _isModified = true;
                  });
                },
              ),
              trailing: SizedBox(
                width: 36,
                child: Text(
                  '$_maxResults',
                  textAlign: TextAlign.end,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includeAnswer,
              title: Text(l10n.settingsAiWebSearchIncludeAnswer),
              onChanged: (value) {
                setState(() {
                  _includeAnswer = value;
                  _isModified = true;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includeRawContent,
              title: Text(l10n.settingsAiWebSearchIncludeRawContent),
              onChanged: (value) {
                setState(() {
                  _includeRawContent = value;
                  _isModified = true;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includeImages,
              title: Text(l10n.settingsAiWebSearchIncludeImages),
              onChanged: (value) {
                setState(() {
                  _includeImages = value;
                  _isModified = true;
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AnxButton.outlined(
                onPressed: _isTesting ? null : _testConnection,
                isLoading: _isTesting,
                child: Text(l10n.settingsAiProviderTestConnection),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TavilySearchConfig _buildDraftConfig() {
    return TavilySearchConfig(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      topic: _topic,
      searchDepth: _searchDepth,
      maxResults: _maxResults,
      includeAnswer: _includeAnswer,
      includeRawContent: _includeRawContent,
      includeImages: _includeImages,
    );
  }

  Future<void> _save() async {
    Prefs().tavilySearchConfig = _buildDraftConfig();
    final enabledIds = Set<String>.from(Prefs().enabledAiToolIds);
    if (_toolEnabled) {
      enabledIds.add(webSearchToolId);
    } else {
      enabledIds.remove(webSearchToolId);
    }
    Prefs().enabledAiToolIds = enabledIds.toList();

    if (!mounted) return;
    setState(() {
      _isModified = false;
    });
    AnxToast.show(L10n.of(context).commonSaveSuccess);
  }

  Future<void> _testConnection() async {
    final l10n = L10n.of(context);
    final config = _buildDraftConfig();
    if (!config.hasApiKey) {
      AnxToast.show(l10n.settingsAiWebSearchStatusMissingKey);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final repository = TavilySearchRepository(config: config);
      await repository.testConnection();
      if (!mounted) return;
      AnxToast.show(l10n.settingsAiWebSearchTestSuccess);
    } catch (error) {
      if (!mounted) return;
      AnxToast.show('${l10n.settingsAiWebSearchTestFailed}: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _markModified() {
    if (_isModified) {
      return;
    }
    setState(() {
      _isModified = true;
    });
  }

  String _topicLabel(L10n l10n, TavilySearchTopic topic) {
    switch (topic) {
      case TavilySearchTopic.general:
        return l10n.settingsAiWebSearchTopicGeneral;
      case TavilySearchTopic.news:
        return l10n.settingsAiWebSearchTopicNews;
      case TavilySearchTopic.finance:
        return l10n.settingsAiWebSearchTopicFinance;
    }
  }

  String _depthLabel(L10n l10n, TavilySearchDepth depth) {
    switch (depth) {
      case TavilySearchDepth.basic:
        return l10n.settingsAiWebSearchDepthBasic;
      case TavilySearchDepth.advanced:
        return l10n.settingsAiWebSearchDepthAdvanced;
      case TavilySearchDepth.fast:
        return l10n.settingsAiWebSearchDepthFast;
      case TavilySearchDepth.ultraFast:
        return l10n.settingsAiWebSearchDepthUltraFast;
    }
  }
}
