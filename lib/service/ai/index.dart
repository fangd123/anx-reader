import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_key_rotator.dart';
import 'package:anx_reader/service/ai/deepseek_support.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

final CancelableLangchainRunner _runner = CancelableLangchainRunner();

// Global request timestamps list for RPM throttling
final List<DateTime> _aiRequestTimestamps = [];

/// Throttle AI requests if RPM limit is configured (sliding 1-minute window).
Future<void> _throttleIfNeeded() async {
  final rpm = Prefs().aiRpm;
  if (rpm <= 0) return;
  final now = DateTime.now();
  final windowStart = now.subtract(const Duration(minutes: 1));
  _aiRequestTimestamps.removeWhere((ts) => ts.isBefore(windowStart));
  if (_aiRequestTimestamps.length >= rpm) {
    final oldest = _aiRequestTimestamps.first;
    final waitUntil = oldest.add(const Duration(minutes: 1));
    final waitDuration = waitUntil.difference(DateTime.now());
    if (waitDuration > Duration.zero) {
      await Future.delayed(waitDuration);
    }
    final newNow = DateTime.now();
    _aiRequestTimestamps.removeWhere(
        (ts) => ts.isBefore(newNow.subtract(const Duration(minutes: 1))));
  }
  _aiRequestTimestamps.add(DateTime.now());
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  WidgetRef? ref,
}) {
  if (useAgent) {
    assert(ref != null, 'ref must be provided when useAgent is true');
  }
  LangchainAiRegistry registry = LangchainAiRegistry(ref);

  return _generateStream(
      messages: messages,
      identifier: identifier,
      overrideConfig: config,
      regenerate: regenerate,
      useAgent: useAgent,
      registry: registry);
}

void cancelActiveAiRequest() {
  _runner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  required LangchainAiRegistry registry,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  LangchainAiConfig config;

  // Try to use new provider system first if ref is available
  if (registry.ref != null && overrideConfig == null) {
    try {
      final notifier = registry.ref!.read(aiProvidersProvider.notifier);
      // If a specific provider id was passed, use it; otherwise use the default
      final AiProvider? provider = identifier != null
          ? notifier.getProviderById(identifier)
          : notifier.getSelectedProvider();
      if (provider != null &&
          provider.enabled &&
          AiKeyRotator.hasValidKey(provider)) {
        final apiKey = AiKeyRotator.getNextKey(provider);
        if (apiKey != null) {
          config = LangchainAiConfig.fromProvider(
            providerId: provider.id,
            model: provider.model,
            apiKey: apiKey,
            url: provider.url,
            reasoningEffort: provider.reasoningEffort,
          );
          final sanitizedMessages = _sanitizeMessagesForPrompt(
            messages,
            preserveAssistantReasoningReplay:
                config.deepSeekReasoningReplayEnabled,
          );

          AnxLog.info(
              'aiGenerateStream (new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

          final pipeline = registry.resolveByProtocol(provider.protocol, config,
              useAgent: useAgent);
          final model = pipeline.model;

          await _throttleIfNeeded();
          yield* _executeStream(
            model: model,
            pipeline: pipeline,
            sanitizedMessages: sanitizedMessages,
            useAgent: useAgent,
          );

          // Advance key index for round-robin rotation after successful call
          registry.ref!
              .read(aiProvidersProvider.notifier)
              .advanceKeyIndex(provider.id);
          return;
        }
      }
    } catch (e) {
      AnxLog.warning(
          'Failed to use new provider system, falling back to legacy: $e');
    }
  }

  // Try new provider system without ref (reads directly from Prefs storage)
  if (overrideConfig == null) {
    try {
      final rawProviders = Prefs().getAiProviders();
      if (rawProviders.isNotEmpty) {
        final providers = rawProviders
            .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
            .map(normalizeDeepSeekProvider)
            .toList();

        AiProvider? provider;
        if (identifier != null) {
          try {
            provider = providers.firstWhere((p) => p.id == identifier);
          } catch (_) {
            provider = null;
          }
        } else {
          final selectedId = Prefs().selectedAiService;
          try {
            provider = providers.firstWhere((p) => p.id == selectedId);
          } catch (_) {}
          provider ??= providers.where((p) => p.enabled).firstOrNull;
        }

        if (provider != null &&
            provider.enabled &&
            AiKeyRotator.hasValidKey(provider)) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
            );
            final sanitizedMessages = _sanitizeMessagesForPrompt(
              messages,
              preserveAssistantReasoningReplay:
                  config.deepSeekReasoningReplayEnabled,
            );

            AnxLog.info(
                'aiGenerateStream (no-ref new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent);
            final model = pipeline.model;

            await _throttleIfNeeded();
            yield* _executeStream(
              model: model,
              pipeline: pipeline,
              sanitizedMessages: sanitizedMessages,
              useAgent: useAgent,
            );

            // Advance key index in persistent storage for round-robin rotation
            final updatedProviders = providers.map((p) {
              if (p.id == provider!.id) {
                return p.copyWith(
                    keyIndex: p.keyIndex + 1, updatedAt: DateTime.now());
              }
              return p;
            }).toList();
            Prefs().saveAiProviders(updatedProviders);
            return;
          }
        }
      }
    } catch (e) {
      AnxLog.warning(
          'Failed to use no-ref new provider system, falling back to legacy: $e');
    }
  }

  // Fall back to legacy system
  final selectedIdentifier = identifier ?? Prefs().selectedAiService;
  final savedConfig = Prefs().getAiConfig(selectedIdentifier);
  if (savedConfig.isEmpty &&
      (overrideConfig == null || overrideConfig.isEmpty)) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      yield L10n.of(context).aiServiceNotConfigured;
    } else {
      yield 'AI service not configured';
    }
    return;
  }

  config = LangchainAiConfig.fromPrefs(selectedIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(selectedIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }
  final sanitizedMessages = _sanitizeMessagesForPrompt(
    messages,
    preserveAssistantReasoningReplay: config.deepSeekReasoningReplayEnabled,
  );

  AnxLog.info(
      'aiGenerateStream (legacy): $selectedIdentifier, model: ${config.model}, baseUrl: ${config.baseUrl}');

  final pipeline = registry.resolve(config, useAgent: useAgent);
  final model = pipeline.model;

  await _throttleIfNeeded();
  yield* _executeStream(
    model: model,
    pipeline: pipeline,
    sanitizedMessages: sanitizedMessages,
    useAgent: useAgent,
  );
}

/// Execute the AI stream with the given model and pipeline
Stream<String> _executeStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
}) async* {
  Stream<String> stream;
  if (useAgent) {
    final inputMessage = _latestUserMessage(sanitizedMessages);
    if (inputMessage == null) {
      yield 'No user input provided';
      return;
    }

    final tools = pipeline.tools;
    if (tools.isEmpty) {
      yield 'Agent mode not supported for this provider.';
      return;
    }

    final historyMessages = sanitizedMessages
        .sublist(0, sanitizedMessages.length - 1)
        .toList(growable: false);

    stream = _runner.streamAgent(
      model: model,
      tools: tools,
      history: historyMessages,
      input: inputMessage,
      systemMessage: pipeline.systemMessage,
    );
  } else {
    final prompt = PromptValue.chat(sanitizedMessages);
    stream = _runner.stream(model: model, prompt: prompt);
  }

  var buffer = '';

  try {
    await for (final chunk in stream) {
      buffer = chunk;
      yield buffer;
    }
  } catch (error, stack) {
    final mapped = _mapError(error);
    AnxLog.severe('AI error: $mapped\n$stack');
    yield mapped;
  } finally {
    try {
      model.close();
    } catch (_) {}
  }
}

String _mapError(Object error) {
  final base = 'Error: ';

  if (error is TimeoutException) {
    return '${base}Request timed out';
  }

  if (error is SocketException) {
    return '${base}Network error: ${error.message}';
  }

  final message = error.toString().toLowerCase();

  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return '${base}Authentication failed. Please verify API key.';
  }

  if (message.contains('429') || message.contains('rate limit')) {
    return '${base}Rate limit reached. Try again later.';
  }

  if (message.contains('timeout')) {
    return '${base}Request timed out';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return '${base}Network error: ${error.toString()}';
  }

  return '$base${error.toString()}';
}

List<ChatMessage> sanitizeMessagesForPrompt(
  List<ChatMessage> messages, {
  bool preserveAssistantReasoningReplay = false,
}) {
  final sanitized = <ChatMessage>[];

  for (final message in messages) {
    if (message is AIChatMessage) {
      if (preserveAssistantReasoningReplay) {
        final recovered = _recoverDeepSeekReplayMessages(message);
        if (recovered.length != 1 || !identical(recovered.single, message)) {
          sanitized.addAll(recovered);
          continue;
        }
      }

      if (message.reasoningContent.isNotEmpty) {
        if (preserveAssistantReasoningReplay) {
          sanitized.add(message);
          continue;
        }
        sanitized.add(AIChatMessage(
          content: message.content,
          toolCalls: message.toolCalls,
        ));
        continue;
      }
      final plainText = reasoningContentToPlainText(message.content);
      if (plainText == message.content) {
        sanitized.add(message);
        continue;
      }
      sanitized.add(AIChatMessage(
        content: plainText,
        toolCalls: message.toolCalls,
      ));
      continue;
    }

    sanitized.add(message);
  }

  return sanitized;
}

List<ChatMessage> _sanitizeMessagesForPrompt(
  List<ChatMessage> messages, {
  bool preserveAssistantReasoningReplay = false,
}) {
  return sanitizeMessagesForPrompt(
    messages,
    preserveAssistantReasoningReplay: preserveAssistantReasoningReplay,
  );
}

String? _latestUserMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message.contentAsString;
    }
  }
  return null;
}

List<ChatMessage> _recoverDeepSeekReplayMessages(AIChatMessage message) {
  if (message.toolCalls.isNotEmpty || message.reasoningContent.isNotEmpty) {
    return [message];
  }

  final parsed = parseReasoningContent(message.content);
  if (parsed.timeline.isEmpty) {
    return [message];
  }

  final recovered = <ChatMessage>[];
  var cursor = 0;
  var replayRound = 0;

  while (cursor < parsed.timeline.length) {
    final reasoningBuffer = StringBuffer();
    while (cursor < parsed.timeline.length) {
      final entry = parsed.timeline[cursor];
      if (entry.type != ParsedReasoningEntryType.reply ||
          entry.section != ParsedReasoningSection.reasoning) {
        break;
      }
      final text = entry.text;
      if (text != null) {
        reasoningBuffer.write(text);
      }
      cursor += 1;
    }

    final reasoning = reasoningBuffer.toString();
    if (cursor >= parsed.timeline.length) {
      if (reasoning.isNotEmpty) {
        recovered.add(
          AIChatMessage(
            content: '',
            reasoningContent: reasoning,
          ),
        );
      }
      break;
    }

    final current = parsed.timeline[cursor];
    if (current.type == ParsedReasoningEntryType.tool) {
      replayRound += 1;
      final toolSteps = <ParsedToolStep>[];
      while (cursor < parsed.timeline.length &&
          parsed.timeline[cursor].type == ParsedReasoningEntryType.tool) {
        final step = parsed.timeline[cursor].toolStep;
        if (step != null) {
          toolSteps.add(step);
        }
        cursor += 1;
      }

      if (toolSteps.isNotEmpty) {
        final assistantToolCalls = <AIChatMessageToolCall>[];
        final toolMessages = <ToolChatMessage>[];

        for (var i = 0; i < toolSteps.length; i++) {
          final step = toolSteps[i];
          final toolCallId = 'deepseek_replay_${replayRound}_${i + 1}';
          final rawInput =
              step.input?.trim().isNotEmpty == true ? step.input!.trim() : '{}';
          assistantToolCalls.add(
            AIChatMessageToolCall(
              id: toolCallId,
              name: step.name,
              argumentsRaw: rawInput,
              arguments: _decodeToolCallArguments(rawInput),
            ),
          );
          toolMessages.add(
            ToolChatMessage(
              toolCallId: toolCallId,
              content: _toolObservationForReplay(step),
            ),
          );
        }

        recovered.add(
          AIChatMessage(
            content: '',
            reasoningContent: reasoning,
            toolCalls: assistantToolCalls,
          ),
        );
        recovered.addAll(toolMessages);
        continue;
      }
    }

    final replyBuffer = StringBuffer();
    while (cursor < parsed.timeline.length) {
      final entry = parsed.timeline[cursor];
      if (entry.type == ParsedReasoningEntryType.tool ||
          entry.section == ParsedReasoningSection.reasoning) {
        break;
      }
      final text = entry.text;
      if (text != null) {
        replyBuffer.write(text);
      }
      cursor += 1;
    }

    final reply = replyBuffer.toString();
    if (reply.isNotEmpty || reasoning.isNotEmpty) {
      recovered.add(
        AIChatMessage(
          content: reply,
          reasoningContent: reasoning,
        ),
      );
    }
  }

  if (recovered.isEmpty) {
    return [message];
  }

  if (recovered.length > 1) {
    AnxLog.info(
      'Recovered ${recovered.length} DeepSeek replay messages from stored transcript.',
    );
  }
  return recovered;
}

Map<String, dynamic> _decodeToolCallArguments(String rawInput) {
  try {
    final decoded = jsonDecode(rawInput);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
  } catch (_) {
    // Fall through to empty map for malformed historical inputs.
  }
  return const {};
}

String _toolObservationForReplay(ParsedToolStep step) {
  final output = step.output?.trim();
  if (output != null && output.isNotEmpty) {
    return output;
  }
  final error = step.error?.trim();
  if (error != null && error.isNotEmpty) {
    return error;
  }
  return '';
}
