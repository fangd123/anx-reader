import 'package:anx_reader/l10n/generated/L10n.dart';
import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/search_content_group.dart';
import 'package:anx_reader/models/search_note_group.dart';
import 'package:anx_reader/providers/search.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/utils/error_handler.dart';
import 'package:anx_reader/widgets/book_notes/book_note_tile.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(() {
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = '';
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final booksAndNotesAsync = ref.watch(searchResultProvider);
    final contentAsync = ref.watch(searchContentResultProvider);

    var appBar = AppBar(
      forceMaterialTransparency: true,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: L10n.of(context).searchBooksOrNotes,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearQuery,
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(32)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (value) {
            _debounce?.cancel();
            ref.read(searchQueryProvider.notifier).state = value;
          },
        ),
      ),
    );

    return Scaffold(
      appBar: appBar,
      body: query.trim().isEmpty
          ? Center(
              child: Text(
                L10n.of(context).startTypingToSearch,
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  spacing: 24,
                  children: [
                    booksAndNotesAsync.when(
                      data: (result) {
                        return Column(
                          spacing: 24,
                          children: [
                            _SearchResult(
                              title: L10n.of(context).books,
                              empty: result.books.isEmpty,
                              child: _SearchBookResult(books: result.books),
                            ),
                            _SearchResult(
                              title: L10n.of(context).notes,
                              empty: result.noteGroups.isEmpty,
                              child:
                                  _SearchNoteResult(group: result.noteGroups),
                            ),
                          ],
                        );
                      },
                      loading: () => const _LoadingSearchSections(
                        titles: ['books', 'notes'],
                      ),
                      error: (error, stack) {
                        return errorHandler(error);
                      },
                    ),
                    contentAsync.when(
                      data: (groups) {
                        return _SearchResult(
                          title: L10n.of(context).searchContent,
                          empty: groups.isEmpty,
                          child: _SearchContentResult(groups: groups),
                        );
                      },
                      loading: () => _LoadingSearchSection(
                        title: L10n.of(context).searchContent,
                      ),
                      error: (error, stack) {
                        return _SearchErrorSection(
                          title: L10n.of(context).searchContent,
                          error: error,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SearchResult extends ConsumerWidget {
  const _SearchResult({
    required this.title,
    required this.child,
    required this.empty,
  });

  final String title;
  final Widget child;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge!
              .copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        FilledContainer(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          child: empty
              ? Center(
                  child: Text(
                    L10n.of(context).nothingHere,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : child,
        ),
      ],
    );
  }
}

class _SearchBookResult extends ConsumerWidget {
  const _SearchBookResult({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMany = books.length > 6;
    final manyFactor = isMany ? 2 : 1;

    final coverWidth = Prefs().bookCoverWidth / 1.5;
    final tileHeight = coverWidth * 2.1 + 55;
    final booksSectionHeight = tileHeight * manyFactor + 32;

    return SizedBox(
      height: booksSectionHeight,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: manyFactor,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.1 / 1,
        ),
        itemBuilder: (context, index) {
          final book = books[index];
          return BookItem(book: book);
        },
        itemCount: books.length,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }
}

class _SearchNoteResult extends ConsumerWidget {
  const _SearchNoteResult({required this.group});

  final List<SearchNoteGroup> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(spacing: 18, children: [
      ...group.map((item) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.book.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: 4),
              FilledContainer(
                  radius: 16,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      ...item.notes.map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BookNoteTile(
                            backgroundColor:
                                Theme.of(context).scaffoldBackgroundColor,
                            note: note,
                            margin: EdgeInsets.zero,
                            onTap: () {
                              pushToReadingPage(ref, context, item.book,
                                  cfi: note.cfi);
                            },
                          ),
                        ),
                      ),
                    ],
                  )),
            ],
          ))
    ]);
  }
}

class _SearchContentResult extends ConsumerWidget {
  const _SearchContentResult({required this.groups});

  final List<SearchContentGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      spacing: 14,
      children: groups
          .map(
            (group) => FilledContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.book.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (group.book.author.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      group.book.author,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withAlpha(180),
                          ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ...group.chapters.map(
                    (chapter) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.title.isEmpty
                                ? group.book.title
                                : chapter.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          ...chapter.matches.map(
                            (match) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  pushToReadingPage(
                                    ref,
                                    context,
                                    group.book,
                                    cfi: match.cfi.isEmpty
                                        ? chapter.cfi
                                        : match.cfi,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: match.pre),
                                        TextSpan(
                                          text: match.match,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        TextSpan(text: match.post),
                                      ],
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LoadingSearchSections extends StatelessWidget {
  const _LoadingSearchSections({required this.titles});

  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      spacing: 24,
      children: titles
          .map(
            (title) => _LoadingSearchSection(
              title: title == 'books' ? l10n.books : l10n.notes,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LoadingSearchSection extends StatelessWidget {
  const _LoadingSearchSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return _SearchResult(
      title: title,
      empty: false,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _SearchErrorSection extends StatelessWidget {
  const _SearchErrorSection({
    required this.title,
    required this.error,
  });

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return _SearchResult(
      title: title,
      empty: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          error.toString(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ),
    );
  }
}
