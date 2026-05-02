import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/current_reading_state.dart';
import 'package:anx_reader/service/ai/request_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  test('injects preset and request context as system messages', () {
    final messages = buildRequestScopedSystemMessages(
      temporarySystemPrompt: 'You are a source lookup assistant.',
      temporaryContext: buildReadingRequestContext(
        CurrentReadingState(
          isReading: true,
          book: Book(
            id: 7,
            title: 'Records of the Grand Historian',
            coverPath: '',
            filePath: '',
            lastReadPosition: '',
            readingPercentage: 0.42,
            author: 'Sima Qian',
            isDeleted: false,
            rating: 0,
            createTime: DateTime(2024, 1, 1),
            updateTime: DateTime(2024, 1, 1),
          ),
          cfi: 'epubcfi(/6/2)',
          percentage: 0.42,
          chapterTitle: 'Biographies',
          chapterHref: 'chapter-3.xhtml',
          chapterCurrentPage: 4,
          chapterTotalPages: 12,
        ),
        selectedText: '天下熙熙，皆为利来。',
        contextText: 'A short surrounding paragraph.',
      ),
    );

    expect(messages, hasLength(2));
    expect(messages.first, isA<SystemChatMessage>());
    expect((messages.first as SystemChatMessage).content,
        'You are a source lookup assistant.');

    final contextMessage = messages.last as SystemChatMessage;
    expect(contextMessage.content, contains('## Selected Text'));
    expect(contextMessage.content, contains('天下熙熙，皆为利来。'));
    expect(contextMessage.content, contains('## Surrounding Context'));
    expect(contextMessage.content, contains('Records of the Grand Historian'));
    expect(contextMessage.content, contains('Sima Qian'));
    expect(contextMessage.content, contains('chapter-3.xhtml'));
    expect(contextMessage.content, contains('42.0%'));
  });

  test('does not add scoped messages when preset and context are empty', () {
    final messages = buildRequestScopedSystemMessages();
    expect(messages, isEmpty);
  });

  test('builds reading request context only when there is usable content', () {
    const emptyState = CurrentReadingState();
    expect(buildReadingRequestContext(emptyState), isNull);

    final requestContext = buildReadingRequestContext(
      emptyState,
      selectedText: 'Selected sentence',
    );
    expect(requestContext, isNotNull);
    expect(requestContext!.toSystemPrompt(), contains('Selected sentence'));
  });
}
