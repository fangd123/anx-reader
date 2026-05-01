import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/deepseek_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiReasoningEffort', () {
    test('parses max from code', () {
      expect(AiReasoningEffort.fromCode('max'), AiReasoningEffort.max);
    });
  });

  group('DeepSeek support', () {
    test('detects builtin provider id', () {
      expect(
        isDeepSeekProvider(identifier: 'deepseek', url: null),
        isTrue,
      );
    });

    test('detects official host', () {
      expect(
        isDeepSeekProvider(
          identifier: 'custom',
          url: 'https://api.deepseek.com/v1/chat/completions',
        ),
        isTrue,
      );
    });

    test('defaults DeepSeek reasoning effort to max', () {
      expect(
        defaultReasoningEffortForProvider(
          identifier: 'deepseek',
          url: 'https://api.deepseek.com/v1/chat/completions',
        ),
        AiReasoningEffort.max,
      );
    });

    test('normalizes legacy DeepSeek auto to max only', () {
      final provider = AiProvider(
        id: 'deepseek',
        title: 'DeepSeek',
        url: 'https://api.deepseek.com/v1/chat/completions',
        protocol: AiProtocol.openai,
        reasoningEffort: AiReasoningEffort.auto,
      );

      expect(
        normalizeDeepSeekProvider(provider).reasoningEffort,
        AiReasoningEffort.max,
      );
    });

    test('preserves explicit DeepSeek reasoning effort', () {
      final provider = AiProvider(
        id: 'deepseek',
        title: 'DeepSeek',
        url: 'https://api.deepseek.com/v1/chat/completions',
        protocol: AiProtocol.openai,
        reasoningEffort: AiReasoningEffort.high,
      );

      expect(
        normalizeDeepSeekProvider(provider).reasoningEffort,
        AiReasoningEffort.high,
      );
    });
  });
}
