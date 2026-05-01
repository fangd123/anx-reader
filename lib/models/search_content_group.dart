import 'package:anx_reader/models/book.dart';

class SearchContentGroup {
  SearchContentGroup({
    required this.book,
    required this.chapters,
  });

  final Book book;
  final List<SearchContentChapterResult> chapters;

  int get matchCount =>
      chapters.fold(0, (total, chapter) => total + chapter.matches.length);

  static SearchContentGroup? fromResponse(
    Book book,
    Map<String, dynamic> response,
  ) {
    final rawResults = response['results'];
    if (rawResults is! List) {
      return null;
    }

    final chapters = rawResults
        .whereType<Map>()
        .map((item) => SearchContentChapterResult.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.matches.isNotEmpty)
        .toList(growable: false);

    if (chapters.isEmpty) {
      return null;
    }

    return SearchContentGroup(
      book: book,
      chapters: chapters,
    );
  }
}

class SearchContentChapterResult {
  SearchContentChapterResult({
    required this.title,
    required this.cfi,
    required this.matches,
  });

  final String title;
  final String cfi;
  final List<SearchContentMatch> matches;

  static SearchContentChapterResult fromJson(Map<String, dynamic> json) {
    final rawMatches = json['matches'];
    return SearchContentChapterResult(
      title: (json['chapterTitle'] as String? ?? '').trim(),
      cfi: (json['chapterCfi'] as String? ?? '').trim(),
      matches: rawMatches is! List
          ? const []
          : rawMatches
              .whereType<Map>()
              .map((item) =>
                  SearchContentMatch.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false),
    );
  }
}

class SearchContentMatch {
  SearchContentMatch({
    required this.cfi,
    required this.pre,
    required this.match,
    required this.post,
  });

  final String cfi;
  final String pre;
  final String match;
  final String post;

  String buildPreview() {
    return '$pre$match$post'.trim();
  }

  static SearchContentMatch fromJson(Map<String, dynamic> json) {
    return SearchContentMatch(
      cfi: (json['cfi'] as String? ?? '').trim(),
      pre: (json['pre'] as String? ?? '').trim(),
      match: (json['match'] as String? ?? '').trim(),
      post: (json['post'] as String? ?? '').trim(),
    );
  }
}
