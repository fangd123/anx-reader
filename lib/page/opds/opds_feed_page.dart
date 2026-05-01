import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/opds_catalog.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/opds/opds_service.dart';
import 'package:anx_reader/service/opds/opds_types.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpdsFeedPage extends ConsumerStatefulWidget {
  const OpdsFeedPage({
    super.key,
    required this.catalog,
    this.feedUrl,
    this.initialTitle,
    this.overrideFeedFuture,
  });

  final OpdsCatalog catalog;
  final String? feedUrl;
  final String? initialTitle;
  final Future<OpdsFeed> Function()? overrideFeedFuture;

  @override
  ConsumerState<OpdsFeedPage> createState() => _OpdsFeedPageState();
}

class _OpdsFeedPageState extends ConsumerState<OpdsFeedPage> {
  final OpdsService _opdsService = OpdsService();
  late Future<OpdsFeed> _feedFuture;
  OpdsFeed? _lastFeed;

  @override
  void initState() {
    super.initState();
    _feedFuture = _loadFeed();
  }

  Future<OpdsFeed> _loadFeed() {
    final override = widget.overrideFeedFuture;
    if (override != null) {
      return override();
    }
    return _opdsService.fetchFeed(widget.catalog, url: widget.feedUrl);
  }

  Future<void> _refresh() async {
    final future = _loadFeed();
    setState(() {
      _feedFuture = future;
    });
    await future;
  }

  Future<void> _downloadAndImport(
    OpdsPublication publication,
    OpdsAcquisition acquisition,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(context).opdsDownloadingTitle),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child:
                  Text(L10n.of(context).opdsDownloadingBook(publication.title)),
            ),
          ],
        ),
      ),
    );

    try {
      final file = await _opdsService.downloadPublication(
        catalog: widget.catalog,
        publication: publication,
        acquisition: acquisition,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      importBookList([file], context, ref);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(L10n.of(context).commonError),
          content: Text(L10n.of(context).opdsDownloadFailed(e.toString())),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.of(context).commonOk),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showPublicationSheet(OpdsPublication publication) async {
    if (publication.acquisitions.length == 1) {
      await _downloadAndImport(publication, publication.acquisitions.first);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PublicationCover(
                      coverUrl: publication.coverUrl,
                      headers: widget.catalog.authHeaders,
                      width: 92,
                      height: 132,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            publication.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if ((publication.author ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              publication.author!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if ((publication.summary ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    publication.summary!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  L10n.of(context).opdsAvailableFormats,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (publication.acquisitions.isEmpty)
                  Text(L10n.of(context).opdsNoSupportedDownload)
                else
                  ...publication.acquisitions.map(
                    (acquisition) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: Text(
                          L10n.of(context)
                              .opdsImportFormat(acquisition.formatLabel),
                        ),
                        subtitle: acquisition.title == null ||
                                acquisition.title!.trim().isEmpty
                            ? null
                            : Text(acquisition.title!.trim()),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _downloadAndImport(publication, acquisition);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openNavigation(OpdsNavigationEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpdsFeedPage(
          catalog: widget.catalog,
          feedUrl: entry.url,
          initialTitle: entry.title,
        ),
      ),
    );
  }

  Future<void> _openSearchSheet(OpdsSearchLink searchLink) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).opdsSearchTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if ((searchLink.title ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  searchLink.title!.trim(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  hintText: L10n.of(context).opdsSearchHint,
                ),
                onSubmitted: (value) {
                  Navigator.of(sheetContext).pop();
                  _openSearchResult(searchLink, value);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _openSearchResult(searchLink, controller.text);
                  },
                  icon: const Icon(Icons.search),
                  label: Text(L10n.of(context).commonSearch),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSearchResult(OpdsSearchLink searchLink, String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpdsSearchResultPage(
          catalog: widget.catalog,
          searchLink: searchLink,
          initialQuery: normalizedQuery,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialTitle ?? widget.catalog.displayName),
        actions: [
          FutureBuilder<OpdsFeed>(
            future: _feedFuture,
            builder: (context, snapshot) {
              final searchLink = snapshot.data?.search ?? _lastFeed?.search;
              if (searchLink == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                onPressed: () => _openSearchSheet(searchLink),
                icon: const Icon(Icons.search),
              );
            },
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<OpdsFeed>(
        future: _feedFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      L10n.of(context).opdsFeedLoadFailed(
                        snapshot.error.toString(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: Text(L10n.of(context).commonRetry),
                    ),
                  ],
                ),
              ),
            );
          }

          final feed = snapshot.data!;
          _lastFeed = feed;
          return _OpdsFeedContent(
            feed: feed,
            catalog: widget.catalog,
            onRefresh: _refresh,
            onOpenNavigation: _openNavigation,
            onOpenPublication: _showPublicationSheet,
            onQuickImport: _downloadAndImport,
          );
        },
      ),
    );
  }
}

class OpdsSearchResultPage extends ConsumerStatefulWidget {
  const OpdsSearchResultPage({
    super.key,
    required this.catalog,
    required this.searchLink,
    required this.initialQuery,
  });

  final OpdsCatalog catalog;
  final OpdsSearchLink searchLink;
  final String initialQuery;

  @override
  ConsumerState<OpdsSearchResultPage> createState() =>
      _OpdsSearchResultPageState();
}

class _OpdsSearchResultPageState extends ConsumerState<OpdsSearchResultPage> {
  final OpdsService _opdsService = OpdsService();
  late final TextEditingController _queryController;
  late Future<OpdsFeed> _searchFuture;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _searchFuture = _search();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<OpdsFeed> _search() {
    return _opdsService.searchFeed(
      catalog: widget.catalog,
      searchLink: widget.searchLink,
      query: _queryController.text,
    );
  }

  Future<void> _submit() async {
    final future = _search();
    setState(() {
      _searchFuture = future;
    });
    await future;
  }

  Future<void> _quickImport(
    OpdsPublication publication,
    OpdsAcquisition acquisition,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(context).opdsDownloadingTitle),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child:
                  Text(L10n.of(context).opdsDownloadingBook(publication.title)),
            ),
          ],
        ),
      ),
    );

    try {
      final file = await _opdsService.downloadPublication(
        catalog: widget.catalog,
        publication: publication,
        acquisition: acquisition,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      importBookList([file], context, ref);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(L10n.of(context).commonError),
          content: Text(L10n.of(context).opdsDownloadFailed(e.toString())),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.of(context).commonOk),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openPublication(OpdsPublication publication) async {
    if (publication.acquisitions.length == 1) {
      await _quickImport(publication, publication.acquisitions.first);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: publication.acquisitions
                  .map(
                    (acquisition) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: Text(
                          L10n.of(context)
                              .opdsImportFormat(acquisition.formatLabel),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _quickImport(publication, acquisition);
                        },
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).opdsSearchTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      hintText: L10n.of(context).opdsSearchHint,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(L10n.of(context).commonSearch),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<OpdsFeed>(
              future: _searchFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        L10n.of(context).opdsFeedLoadFailed(
                          snapshot.error.toString(),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return _OpdsFeedContent(
                  feed: snapshot.data!,
                  catalog: widget.catalog,
                  onRefresh: _submit,
                  onOpenNavigation: (_) {},
                  onOpenPublication: _openPublication,
                  onQuickImport: _quickImport,
                  showNavigationSection: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OpdsFeedContent extends StatelessWidget {
  const _OpdsFeedContent({
    required this.feed,
    required this.catalog,
    required this.onRefresh,
    required this.onOpenNavigation,
    required this.onOpenPublication,
    required this.onQuickImport,
    this.showNavigationSection = true,
  });

  final OpdsFeed feed;
  final OpdsCatalog catalog;
  final Future<void> Function() onRefresh;
  final void Function(OpdsNavigationEntry entry) onOpenNavigation;
  final Future<void> Function(OpdsPublication publication) onOpenPublication;
  final Future<void> Function(
    OpdsPublication publication,
    OpdsAcquisition acquisition,
  ) onQuickImport;
  final bool showNavigationSection;

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = feed.navigation.isNotEmpty || feed.publications.isNotEmpty;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          if ((feed.subtitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                feed.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (!hasItems)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(L10n.of(context).opdsFeedEmpty),
              ),
            ),
          if (showNavigationSection && feed.navigation.isNotEmpty) ...[
            _sectionTitle(context, L10n.of(context).opdsNavigationSection),
            ...feed.navigation.map(
              (entry) => Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(entry.title),
                  subtitle: (entry.summary ?? '').isEmpty
                      ? null
                      : Text(
                          entry.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpenNavigation(entry),
                ),
              ),
            ),
          ],
          if (feed.publications.isNotEmpty) ...[
            _sectionTitle(context, L10n.of(context).opdsBooksSection),
            ...feed.publications.map(
              (publication) => Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: _PublicationCover(
                    coverUrl: publication.coverUrl,
                    headers: catalog.authHeaders,
                  ),
                  title: Text(
                    publication.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((publication.author ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            publication.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if ((publication.summary ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            publication.summary!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (publication.formatLabels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: publication.formatLabels
                                .map(
                                  (format) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withAlpha(120),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      format,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                    ],
                  ),
                  trailing: publication.canImport
                      ? publication.acquisitions.length == 1
                          ? IconButton(
                              onPressed: () => onQuickImport(
                                publication,
                                publication.acquisitions.first,
                              ),
                              icon: const Icon(Icons.download_outlined),
                              tooltip: L10n.of(context).opdsQuickImportTooltip,
                            )
                          : const Icon(Icons.chevron_right)
                      : const Icon(Icons.info_outline),
                  onTap: () => onOpenPublication(publication),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicationCover extends StatelessWidget {
  const _PublicationCover({
    required this.coverUrl,
    required this.headers,
    this.width = 52,
    this.height = 74,
  });

  final String? coverUrl;
  final Map<String, String> headers;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);
    if (coverUrl == null || coverUrl!.isEmpty) {
      return _placeholder(context, borderRadius);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: coverUrl!,
        httpHeaders: headers,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, _) => Container(
          width: width,
          height: height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, _, __) => _placeholder(context, borderRadius),
      ),
    );
  }

  Widget _placeholder(BuildContext context, BorderRadius borderRadius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book_outlined),
    );
  }
}
