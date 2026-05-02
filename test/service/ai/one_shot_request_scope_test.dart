import 'package:anx_reader/models/ai_request_context.dart';
import 'package:anx_reader/models/ai_system_preset.dart';
import 'package:anx_reader/service/ai/one_shot_request_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumes pending preset and context only once for normal sends', () {
    final scope = AiOneShotRequestScope();
    final preset = AiSystemPreset(
      id: 'preset-1',
      name: 'Source Lookup',
      systemPrompt: 'Find the original source first.',
      order: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    const context = AiRequestContext(selectedText: 'A selected passage');

    scope.seed(preset: preset, requestContext: context);

    final firstSend = scope.consume(isRegenerate: false);
    expect(firstSend.systemPrompt, preset.systemPrompt);
    expect(firstSend.requestContext, context);
    expect(scope.pendingPreset, isNull);
    expect(scope.pendingContext, isNull);

    final secondSend = scope.consume(isRegenerate: false);
    expect(secondSend.isEmpty, isTrue);
  });

  test('reuses the last consumed scope when regenerating', () {
    final scope = AiOneShotRequestScope();
    final preset = AiSystemPreset(
      id: 'preset-1',
      name: 'History',
      systemPrompt: 'Explain historical background.',
      order: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    scope.seed(
      preset: preset,
      requestContext: const AiRequestContext(selectedText: '秦王扫六合'),
    );

    scope.consume(isRegenerate: false);
    final regenerate = scope.consume(isRegenerate: true);

    expect(regenerate.systemPrompt, preset.systemPrompt);
    expect(regenerate.requestContext?.selectedText, '秦王扫六合');
  });
}
