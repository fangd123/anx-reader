import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/search_content_group.dart';
import 'package:anx_reader/service/ai/tools/input/book_content_search_input.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:path/path.dart' as path;

typedef SearchableBooksLoader = Future<List<Book>> Function();
typedef BookContentSearchExecutor = Future<Map<String, dynamic>> Function(
  BookContentSearchInput input,
);
typedef BookSearchabilityEvaluator = bool Function(Book book);

class LibraryContentSearchService {
  LibraryContentSearchService({
    SearchableBooksLoader? booksLoader,
    BookContentSearchRepository? bookContentSearchRepository,
    BookContentSearchExecutor? searchExecutor,
    BookSearchabilityEvaluator? isBookSearchable,
    this.maxBooksToScan = 12,
    this.maxMatchingBooks = 6,
    this.maxChapterResultsPerBook = 2,
    this.maxSnippetsPerChapter = 2,
    this.maxSnippetCharacters = 120,
  })  : _booksLoader = booksLoader ?? _defaultBooksLoader,
        _bookContentSearchRepository =
            bookContentSearchRepository ?? BookContentSearchRepository(),
        _isBookSearchable = isBookSearchable ?? _defaultIsBookSearchable {
    _searchExecutor = searchExecutor ?? _bookContentSearchRepository.search;
  }

  final SearchableBooksLoader _booksLoader;
  final BookContentSearchRepository _bookContentSearchRepository;
  late final BookContentSearchExecutor _searchExecutor;
  final BookSearchabilityEvaluator _isBookSearchable;
  final int maxBooksToScan;
  final int maxMatchingBooks;
  final int maxChapterResultsPerBook;
  final int maxSnippetsPerChapter;
  final int maxSnippetCharacters;

  static const Set<String> _searchableExtensions = {
    'epub',
    'mobi',
    'azw3',
    'fb2',
    'pdf',
  };

  Future<List<SearchContentGroup>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    final books = await _booksLoader();
    final searchableBooks = books.where(_isBookSearchable).take(maxBooksToScan);
    final groups = <SearchContentGroup>[];

    for (final book in searchableBooks) {
      if (groups.length >= maxMatchingBooks) {
        break;
      }

      try {
        final response = await _searchExecutor(
          BookContentSearchInput(
            bookId: book.id,
            keyword: query,
            maxResults: maxChapterResultsPerBook,
            maxSnippets: maxSnippetsPerChapter,
            maxCharacters: maxSnippetCharacters,
          ),
        );

        final group = SearchContentGroup.fromResponse(book, response);
        if (group != null) {
          groups.add(group);
        }
      } on Object catch (error, stackTrace) {
        AnxLog.warning(
          'LibraryContentSearchService: skipped book=${book.id} title="${book.title}" during full-text search: $error\n$stackTrace',
        );
      }
    }

    return groups;
  }

  static Future<List<Book>> _defaultBooksLoader() {
    return bookDao.selectNotDeleteBooks();
  }

  static bool _defaultIsBookSearchable(Book book) {
    if (book.isDeleted) {
      return false;
    }

    final file = File(book.fileFullPath);
    if (!file.existsSync()) {
      return false;
    }

    final extension = path.extension(book.fileFullPath).toLowerCase();
    final normalized =
        extension.startsWith('.') ? extension.substring(1) : extension;
    return _searchableExtensions.contains(normalized);
  }
}
