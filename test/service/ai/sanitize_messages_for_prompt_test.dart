import 'package:anx_reader/service/ai/index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  group('sanitizeMessagesForPrompt', () {
    test('preserves assistant reasoning replay for DeepSeek tool history', () {
      final messages = <ChatMessage>[
        const HumanChatMessage(content: ChatMessageContentText(text: 'hi')),
        const AIChatMessage(
          content: '',
          reasoningContent: 'I need to call a tool first',
          toolCalls: [
            AIChatMessageToolCall(
              id: 'call_1',
              name: 'get_weather',
              argumentsRaw: '{"city":"Hangzhou"}',
              arguments: {'city': 'Hangzhou'},
            ),
          ],
        ),
      ];

      final sanitized = sanitizeMessagesForPrompt(
        messages,
        preserveAssistantReasoningReplay: true,
      );

      final assistant = sanitized[1] as AIChatMessage;
      expect(assistant.reasoningContent, 'I need to call a tool first');
      expect(assistant.toolCalls, hasLength(1));
    });

    test('removes assistant reasoning replay for non-DeepSeek history', () {
      final messages = <ChatMessage>[
        const HumanChatMessage(content: ChatMessageContentText(text: 'hi')),
        const AIChatMessage(
          content: '',
          reasoningContent: 'internal reasoning',
          toolCalls: [
            AIChatMessageToolCall(
              id: 'call_1',
              name: 'get_weather',
              argumentsRaw: '{"city":"Hangzhou"}',
              arguments: {'city': 'Hangzhou'},
            ),
          ],
        ),
      ];

      final sanitized = sanitizeMessagesForPrompt(messages);

      final assistant = sanitized[1] as AIChatMessage;
      expect(assistant.reasoningContent, isEmpty);
      expect(assistant.toolCalls, hasLength(1));
    });

    test(
        'converts think envelope content to plain text when no separate reasoning exists',
        () {
      final messages = <ChatMessage>[
        const AIChatMessage(
          content: '<think>plan</think>\nanswer',
        ),
      ];

      final sanitized = sanitizeMessagesForPrompt(messages);

      final assistant = sanitized.single as AIChatMessage;
      expect(assistant.content, isNot(contains('<think>')));
      expect(assistant.content, contains('plan'));
      expect(assistant.content, contains('answer'));
      expect(assistant.reasoningContent, isEmpty);
    });

    test('reconstructs stored agent transcript into DeepSeek replay messages',
        () {
      const storedTranscript = AIChatMessage(
        content:
            '<think><think-block text_b64=\'SSBuZWVkIHRoZSBjdXJyZW50IHRpbWUu\'/></think>'
            '<tool-step name=\'current_time\' status=\'success\' '
            'input_b64=\'eyJpbmNsdWRlX3RpbWV6b25lIjp0cnVlfQ%3D%3D\' '
            'output_b64=\'eyJsb2NhbElzbyI6IjIwMjYtMDUtMDFUMTQ6NTI6MDBaIn0%3D\'/>'
            '<reply text_b64=\'SXQgaXMgMjAyNi0wNS0wMSAxNDo1Mi4=\'/>',
      );

      final sanitized = sanitizeMessagesForPrompt(
        [storedTranscript],
        preserveAssistantReasoningReplay: true,
      );

      expect(sanitized, hasLength(3));

      final replayAssistant = sanitized[0] as AIChatMessage;
      expect(replayAssistant.reasoningContent, 'I need the current time.');
      expect(replayAssistant.content, isEmpty);
      expect(replayAssistant.toolCalls, hasLength(1));
      expect(replayAssistant.toolCalls.single.name, 'current_time');
      expect(replayAssistant.toolCalls.single.arguments,
          {'include_timezone': true});

      final toolMessage = sanitized[1] as ToolChatMessage;
      expect(toolMessage.toolCallId, replayAssistant.toolCalls.single.id);
      expect(toolMessage.content, '{"localIso":"2026-05-01T14:52:00Z"}');

      final finalAssistant = sanitized[2] as AIChatMessage;
      expect(finalAssistant.content, 'It is 2026-05-01 14:52.');
      expect(finalAssistant.reasoningContent, isEmpty);
    });
  });
}
