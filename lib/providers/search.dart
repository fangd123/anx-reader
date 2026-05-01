import 'package:anx_reader/dao/search_repository.dart';
import 'package:anx_reader/models/search_content_group.dart';
import 'package:anx_reader/models/search_note_group.dart';
import 'package:anx_reader/models/search_result_data.dart';
import 'package:anx_reader/service/search/library_content_search_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return const SearchRepository();
});

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final searchContentRepositoryProvider =
    Provider<LibraryContentSearchService>((ref) {
  return LibraryContentSearchService();
});

final searchResultProvider =
    FutureProvider.autoDispose<SearchResultData>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final repository = ref.watch(searchRepositoryProvider);
  final trimmed = query.trim();

  if (trimmed.isEmpty) {
    return SearchResultData.empty;
  }

  final result = await repository.search(trimmed);
  final noteGroups = result.noteGroups
      .map(
        (entry) => SearchNoteGroup(
          book: entry.book,
          notes: entry.notes,
        ),
      )
      .toList(growable: false);

  return SearchResultData(
    books: result.books,
    noteGroups: noteGroups,
  );
});

final searchContentResultProvider =
    FutureProvider.autoDispose<List<SearchContentGroup>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final repository = ref.watch(searchContentRepositoryProvider);
  final trimmed = query.trim();

  if (trimmed.isEmpty) {
    return const [];
  }

  return repository.search(trimmed);
});
