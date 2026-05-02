import 'package:anx_reader/models/ai_request_context.dart';
import 'package:anx_reader/models/current_reading_state.dart';
import 'package:langchain_core/chat_models.dart';

AiRequestContext? buildReadingRequestContext(
  CurrentReadingState state, {
  String? selectedText,
  String? contextText,
}) {
  final requestContext = AiRequestContext(
    selectedText: selectedText,
    contextText: contextText,
    book: state.book,
    cfi: state.cfi,
    chapterTitle: state.chapterTitle,
    chapterHref: state.chapterHref,
    chapterCurrentPage: state.chapterCurrentPage,
    chapterTotalPages: state.chapterTotalPages,
    readingPercentage: state.percentage,
  );

  return requestContext.hasContent ? requestContext : null;
}

List<ChatMessage> buildRequestScopedSystemMessages({
  String? temporarySystemPrompt,
  AiRequestContext? temporaryContext,
}) {
  final messages = <ChatMessage>[];
  final normalizedSystemPrompt = _normalize(temporarySystemPrompt);
  if (normalizedSystemPrompt != null) {
    messages.add(ChatMessage.system(normalizedSystemPrompt));
  }
  if (temporaryContext != null && temporaryContext.hasContent) {
    messages.add(ChatMessage.system(temporaryContext.toSystemPrompt()));
  }
  return messages;
}

List<ChatMessage> prependRequestScopedSystemMessages(
  List<ChatMessage> messages, {
  String? temporarySystemPrompt,
  AiRequestContext? temporaryContext,
}) {
  final scopedMessages = buildRequestScopedSystemMessages(
    temporarySystemPrompt: temporarySystemPrompt,
    temporaryContext: temporaryContext,
  );
  if (scopedMessages.isEmpty) {
    return messages;
  }
  return [...scopedMessages, ...messages];
}

String? _normalize(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
