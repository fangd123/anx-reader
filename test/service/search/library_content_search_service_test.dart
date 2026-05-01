import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/input/book_content_search_input.dart';
import 'package:anx_reader/service/search/library_content_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryContentSearchService', () {
    test('aggregates matched content by book and skips unsupported books',
        () async {
      final searchedBookIds = <int>[];

      final books = [
        _book(
          id: 1,
          title: 'Matched Book',
          filePath: 'file/matched.epub',
        ),
        _book(
          id: 2,
          title: 'Unsupported Book',
          filePath: 'file/unsupported.txt',
        ),
        _book(
          id: 3,
          title: 'No Match Book',
          filePath: 'file/no-match.epub',
        ),
      ];

      final service = LibraryContentSearchService(
        booksLoader: () async => books,
        isBookSearchable: (book) => book.filePath.endsWith('.epub'),
        searchExecutor: (BookContentSearchInput input) async {
          searchedBookIds.add(input.bookId);
          if (input.bookId == 1) {
            return {
              'results': [
                {
                  'chapterTitle': 'Chapter 1',
                  'chapterCfi': '/6/2[chapter1]',
                  'matches': [
                    {
                      'cfi': '/6/4[match1]',
                      'pre': 'before ',
                      'match': 'needle',
                      'post': ' after',
                    }
                  ],
                }
              ],
            };
          }

          return {
            'results': [],
          };
        },
      );

      final results = await service.search('needle');

      expect(searchedBookIds, [1, 3]);
      expect(results, hasLength(1));
      expect(results.first.book.id, 1);
      expect(results.first.book.title, 'Matched Book');
      expect(results.first.chapters, hasLength(1));
      expect(results.first.chapters.first.title, 'Chapter 1');
      expect(results.first.chapters.first.matches, hasLength(1));
      expect(results.first.chapters.first.matches.first.pre, 'before');
      expect(results.first.chapters.first.matches.first.match, 'needle');
      expect(results.first.chapters.first.matches.first.post, 'after');
    });

    test('returns empty when keyword is blank', () async {
      var invoked = false;
      final service = LibraryContentSearchService(
        booksLoader: () async {
          invoked = true;
          return [];
        },
      );

      final results = await service.search('   ');

      expect(results, isEmpty);
      expect(invoked, isFalse);
    });
  });
}

Book _book({
  required int id,
  required String title,
  required String filePath,
}) {
  return Book(
    id: id,
    title: title,
    coverPath: 'cover/$id.png',
    filePath: filePath,
    lastReadPosition: '',
    readingPercentage: 0,
    author: 'Author $id',
    isDeleted: false,
    description: null,
    rating: 0,
    groupId: 0,
    md5: null,
    createTime: DateTime(2024, 1, id),
    updateTime: DateTime(2024, 2, id),
  );
}
