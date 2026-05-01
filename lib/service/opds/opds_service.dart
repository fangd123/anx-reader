import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/opds_catalog.dart';
import 'package:anx_reader/service/opds/opds_types.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

const String _opdsCatalogProfile = 'opds-catalog';
const String _opdsJsonMime = 'application/opds+json';
const String _acquisitionRelPrefix = 'http://opds-spec.org/acquisition';
const String _previewRel = 'preview';
const Set<String> _coverRels = {
  'http://opds-spec.org/image',
  'http://opds-spec.org/cover',
  'http://opds-spec.org/image/thumbnail',
  'http://opds-spec.org/thumbnail',
};
const Map<String, String> _mimeToExtension = {
  'application/epub+zip': 'epub',
  'application/pdf': 'pdf',
  'application/x-mobipocket-ebook': 'mobi',
  'application/vnd.amazon.mobi8-ebook': 'azw3',
  'application/vnd.amazon.ebook': 'azw3',
  'application/fb2+zip': 'fb2',
  'application/x-fictionbook+xml': 'fb2',
  'text/plain': 'txt',
};
const Set<String> _supportedExtensions = {
  'epub',
  'pdf',
  'mobi',
  'azw3',
  'fb2',
  'txt',
};
const String _defaultAccept =
    'application/opds+json, application/atom+xml, application/xml, text/xml, */*';

class OpdsService {
  Future<OpdsFeed> fetchFeed(OpdsCatalog catalog, {String? url}) async {
    final response = await _performRequest(catalog, url: url ?? catalog.url);
    return OpdsParser.parseFeed(
      body: response.body,
      contentType: response.contentType,
      baseUri: response.responseUri,
    );
  }

  Future<OpdsSearch> resolveSearch({
    required OpdsCatalog catalog,
    required OpdsSearchLink searchLink,
  }) async {
    if (searchLink.isTemplate) {
      return OpdsSearch(
        template: searchLink.url,
        title: searchLink.title,
      );
    }

    final response = await _performRequest(catalog, url: searchLink.url);
    return OpdsParser.parseSearch(
      body: response.body,
      contentType: response.contentType,
      baseUri: response.responseUri,
    );
  }

  Future<OpdsFeed> searchFeed({
    required OpdsCatalog catalog,
    required OpdsSearchLink searchLink,
    required String query,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const FormatException('Search query cannot be empty');
    }

    final search = await resolveSearch(
      catalog: catalog,
      searchLink: searchLink,
    );
    final url = _buildSearchUrl(search, normalizedQuery);
    return fetchFeed(catalog, url: url);
  }

  Future<File> downloadPublication({
    required OpdsCatalog catalog,
    required OpdsPublication publication,
    OpdsAcquisition? acquisition,
  }) async {
    final target = acquisition ?? publication.acquisitions.first;
    final uri = Uri.parse(target.url);
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(_buildRequestHeaders(catalog, accept: '*/*'));
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw HttpException(
          'OPDS download failed with status ${response.statusCode}',
          uri: uri,
        );
      }

      final bytes = await response.stream.toBytes();
      final responseUrl = response.request?.url ?? uri;
      final fileName = _resolveDownloadFileName(
        publication: publication,
        acquisition: target,
        responseUrl: responseUrl,
        responseHeaders: response.headers,
      );

      final tempDir = await getAnxTempDir();
      final file = File(path.join(tempDir.path, fileName));
      if (await file.exists()) {
        await file.delete();
      }
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      client.close();
    }
  }

  Map<String, String> _buildRequestHeaders(
    OpdsCatalog catalog, {
    String accept = _defaultAccept,
  }) {
    return {
      'Accept': accept,
      'User-Agent': 'AnxReader OPDS',
      ...catalog.authHeaders,
    };
  }

  Future<_FetchedContent> _performRequest(
    OpdsCatalog catalog, {
    required String url,
    String? accept,
  }) async {
    final uri = Uri.parse(url);
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(
          _buildRequestHeaders(
            catalog,
            accept: accept ?? _defaultAccept,
          ),
        );
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw HttpException(
          'OPDS request failed with status ${response.statusCode}',
          uri: uri,
        );
      }

      final bytes = await response.stream.toBytes();
      return _FetchedContent(
        body: utf8.decode(bytes, allowMalformed: true),
        contentType: response.headers['content-type'],
        responseUri: response.request?.url ?? uri,
      );
    } finally {
      client.close();
    }
  }

  String _buildSearchUrl(OpdsSearch search, String query) {
    final values = {
      'searchTerms': query,
      'count': '50',
      'startIndex': '0',
      'startPage': '0',
      ...search.defaults,
    };

    return search.template.replaceAllMapped(
      RegExp(r'{([^}]+)}'),
      (match) {
        final raw = match.group(1)!;
        final optional = raw.endsWith('?');
        final name = optional ? raw.substring(0, raw.length - 1) : raw;
        final key = name.contains(':') ? name.split(':').last : name;
        final value = values[key] ?? '';
        return Uri.encodeQueryComponent(value);
      },
    );
  }

  String _resolveDownloadFileName({
    required OpdsPublication publication,
    required OpdsAcquisition acquisition,
    required Uri responseUrl,
    required Map<String, String> responseHeaders,
  }) {
    final disposition = responseHeaders['content-disposition'];
    final contentType = responseHeaders['content-type'];

    String? rawName = _extractFileNameFromContentDisposition(disposition);
    rawName ??= path.basename(responseUrl.path);
    rawName = rawName.trim();

    String baseName;
    String extension = '';

    if (rawName.isEmpty || rawName == '/') {
      baseName = publication.title.trim().isEmpty
          ? 'opds-book'
          : publication.title.trim();
    } else {
      baseName = path.basenameWithoutExtension(rawName);
      extension = path.extension(rawName).replaceFirst('.', '').toLowerCase();
    }

    extension = extension.isNotEmpty
        ? extension
        : _guessExtension(
              contentType: contentType,
              mimeType: acquisition.type,
              url: acquisition.url,
            ) ??
            '';

    final sanitizedBase = _sanitizeFileName(baseName);
    final suffix = DateTime.now().millisecondsSinceEpoch;
    return extension.isEmpty
        ? '${sanitizedBase}_$suffix'
        : '${sanitizedBase}_$suffix.$extension';
  }

  String? _extractFileNameFromContentDisposition(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.isEmpty) {
      return null;
    }

    final encodedMatch =
        RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(
      contentDisposition,
    );
    if (encodedMatch != null) {
      return Uri.decodeComponent(encodedMatch.group(1)!);
    }

    final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(contentDisposition);
    if (match == null) {
      return null;
    }

    return match.group(1);
  }

  String? _guessExtension({
    String? contentType,
    required String mimeType,
    required String url,
  }) {
    final fromContentType = _extensionFromMime(contentType);
    if (fromContentType != null) {
      return fromContentType;
    }

    final fromMimeType = _extensionFromMime(mimeType);
    if (fromMimeType != null) {
      return fromMimeType;
    }

    final fromUrl = path.extension(Uri.parse(url).path).replaceFirst('.', '');
    if (_supportedExtensions.contains(fromUrl.toLowerCase())) {
      return fromUrl.toLowerCase();
    }

    return null;
  }

  String _sanitizeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) {
      return 'opds-book';
    }
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }

  String? _extensionFromMime(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return null;
    }
    final normalized = contentType.split(';').first.trim().toLowerCase();
    return _mimeToExtension[normalized];
  }
}

class OpdsParser {
  static OpdsFeed parseFeed({
    required String body,
    required Uri baseUri,
    String? contentType,
  }) {
    if (_looksLikeJson(contentType, body)) {
      return _parseJsonFeed(body: body, baseUri: baseUri);
    }

    return _parseAtomFeed(body: body, baseUri: baseUri);
  }

  static bool _looksLikeJson(String? contentType, String body) {
    if (contentType != null &&
        contentType.toLowerCase().contains(_opdsJsonMime)) {
      return true;
    }

    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  static OpdsFeed _parseJsonFeed({
    required String body,
    required Uri baseUri,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Invalid OPDS 2 feed payload');
    }

    final root = Map<String, dynamic>.from(decoded);
    final metadata = _asMap(root['metadata']);
    final title = (metadata['title'] as String?)?.trim();
    final subtitle = _cleanText(metadata['subtitle']?.toString());

    final navigation = (root['navigation'] as List<dynamic>? ?? const [])
        .map((entry) => _asMap(entry))
        .map((entry) {
          final href = _resolveUrl(baseUri, entry['href']?.toString());
          if (href == null) return null;
          return OpdsNavigationEntry(
            title: _fallbackTitle(entry['title']?.toString(), href),
            url: href,
            summary: _cleanText(entry['summary']?.toString()),
          );
        })
        .whereType<OpdsNavigationEntry>()
        .toList(growable: false);

    final links = (root['links'] as List<dynamic>? ?? const [])
        .map((item) => _asMap(item))
        .toList(growable: false);

    final publications = (root['publications'] as List<dynamic>? ?? const [])
        .map((entry) => _asMap(entry))
        .map((entry) => _parseJsonPublication(entry, baseUri))
        .whereType<OpdsPublication>()
        .toList(growable: false);

    return OpdsFeed(
      title: title == null || title.isEmpty ? baseUri.host : title,
      subtitle: subtitle,
      navigation: navigation,
      publications: publications,
      search: _findJsonSearchLink(links, baseUri),
    );
  }

  static OpdsPublication? _parseJsonPublication(
    Map<String, dynamic> entry,
    Uri baseUri,
  ) {
    final metadata = _asMap(entry['metadata']);
    final links = (entry['links'] as List<dynamic>? ?? const [])
        .map((item) => _asMap(item))
        .toList(growable: false);
    final acquisitions = links
        .map((link) => _parseJsonAcquisition(link, baseUri))
        .whereType<OpdsAcquisition>()
        .toList(growable: false);

    final images = (entry['images'] as List<dynamic>? ?? const [])
        .map((item) => _asMap(item))
        .toList(growable: false);

    String? coverUrl;
    for (final image in images) {
      coverUrl = _resolveUrl(baseUri, image['href']?.toString());
      if (coverUrl != null) {
        break;
      }
    }

    return OpdsPublication(
      title: _fallbackTitle(metadata['title']?.toString(), baseUri.path),
      author: _joinAuthors(metadata['author'] ?? metadata['authors']),
      summary: _cleanText(
        metadata['description']?.toString() ??
            metadata['summary']?.toString() ??
            entry['summary']?.toString(),
      ),
      coverUrl: coverUrl,
      acquisitions: acquisitions,
    );
  }

  static OpdsAcquisition? _parseJsonAcquisition(
    Map<String, dynamic> link,
    Uri baseUri,
  ) {
    final href = _resolveUrl(baseUri, link['href']?.toString());
    if (href == null) return null;

    final rels = _normalizeRels(link['rel']);
    final type = (link['type'] as String? ?? '').trim();
    if (!_isSupportedAcquisition(rels: rels, type: type, href: href)) {
      return null;
    }

    return OpdsAcquisition(
      url: href,
      type: type,
      rel: rels.isEmpty ? null : rels.first,
      title: link['title']?.toString(),
    );
  }

  static OpdsFeed _parseAtomFeed({
    required String body,
    required Uri baseUri,
  }) {
    final document = XmlDocument.parse(body);
    final root = document.rootElement;
    final entries = _childElements(root, 'entry');
    final rootLinks = _childElements(root, 'link')
        .map((link) => _ParsedLink.fromXml(link, baseUri))
        .toList(growable: false);

    final navigation = <OpdsNavigationEntry>[];
    final publications = <OpdsPublication>[];

    for (final entry in entries) {
      final links = _childElements(entry, 'link')
          .map((link) => _ParsedLink.fromXml(link, baseUri))
          .whereType<_ParsedLink>()
          .toList(growable: false);

      if (_looksLikePublication(links)) {
        publications.add(_parseAtomPublication(entry, links));
      } else {
        final item = _parseAtomNavigation(entry, links);
        if (item != null) {
          navigation.add(item);
        }
      }
    }

    final title = _childText(root, 'title');
    final subtitle = _cleanText(_childText(root, 'subtitle'));

    return OpdsFeed(
      title: title == null || title.isEmpty ? baseUri.host : title,
      subtitle: subtitle,
      navigation: navigation,
      publications: publications,
      search: _findAtomSearchLink(rootLinks),
    );
  }

  static OpdsSearch parseSearch({
    required String body,
    required Uri baseUri,
    String? contentType,
  }) {
    if (_looksLikeJson(contentType, body)) {
      throw const FormatException('Search description must be XML');
    }

    final document = XmlDocument.parse(body);
    final root = document.rootElement;
    final urls = _childElements(root, 'Url');
    if (urls.isEmpty) {
      throw const FormatException('Search description has no Url entries');
    }

    XmlElement? targetUrl;
    int bestScore = -1;
    for (final url in urls) {
      final type = url.getAttribute('type')?.toLowerCase() ?? '';
      final score = _scoreSearchUrlType(type);
      if (score > bestScore) {
        bestScore = score;
        targetUrl = url;
      }
    }
    targetUrl ??= urls.first;

    final template = targetUrl.getAttribute('template');
    if (template == null || template.trim().isEmpty) {
      throw const FormatException('Search description template is missing');
    }

    return OpdsSearch(
      template: _resolveTemplate(baseUri, template.trim()),
      title: (_childText(root, 'LongName') ?? _childText(root, 'ShortName'))
          ?.trim(),
      description: _cleanText(_childText(root, 'Description')),
      defaults: {
        'count': '50',
        'startIndex': targetUrl.getAttribute('indexOffset') ?? '0',
        'startPage': targetUrl.getAttribute('pageOffset') ?? '0',
      },
    );
  }

  static bool _looksLikePublication(List<_ParsedLink> links) {
    for (final link in links) {
      final rels = link.rels;
      if (_isSupportedAcquisition(
          rels: rels, type: link.type, href: link.href)) {
        return true;
      }
    }
    return false;
  }

  static OpdsPublication _parseAtomPublication(
    XmlElement entry,
    List<_ParsedLink> links,
  ) {
    final authorNames = _childElements(entry, 'author')
        .map((author) => _childText(author, 'name'))
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    final acquisitions = links
        .where(
          (link) => _isSupportedAcquisition(
            rels: link.rels,
            type: link.type,
            href: link.href,
          ),
        )
        .map(
          (link) => OpdsAcquisition(
            url: link.href!,
            type: link.type,
            rel: link.rels.isEmpty ? null : link.rels.first,
            title: link.title,
          ),
        )
        .toList(growable: false);

    final coverUrl = links
        .where((link) => link.href != null)
        .firstWhere(
          (link) => link.rels.any(_coverRels.contains),
          orElse: () => const _ParsedLink.empty(),
        )
        .href;

    return OpdsPublication(
      title: _fallbackTitle(_childText(entry, 'title'), 'Untitled'),
      author: authorNames.isEmpty ? null : authorNames.join(', '),
      summary: _cleanText(_entrySummary(entry)),
      coverUrl: coverUrl,
      acquisitions: acquisitions,
    );
  }

  static OpdsNavigationEntry? _parseAtomNavigation(
    XmlElement entry,
    List<_ParsedLink> links,
  ) {
    final link = links.firstWhere(
      (item) => item.href != null && _looksLikeCatalogLink(item.type),
      orElse: () => links.firstWhere(
        (item) => item.href != null,
        orElse: () => const _ParsedLink.empty(),
      ),
    );

    final href = link.href;
    if (href == null) {
      return null;
    }

    return OpdsNavigationEntry(
      title: _fallbackTitle(_childText(entry, 'title'), href),
      url: href,
      summary: _cleanText(_entrySummary(entry)),
    );
  }

  static bool _looksLikeCatalogLink(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains(_opdsJsonMime)) {
      return true;
    }
    if (!normalized.contains('application/atom+xml')) {
      return false;
    }
    return normalized.contains(_opdsCatalogProfile);
  }

  static int _scoreSearchUrlType(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains(_opdsJsonMime)) {
      return 4;
    }
    if (_looksLikeCatalogLink(normalized)) {
      return 3;
    }
    if (normalized.contains('application/atom+xml') ||
        normalized.contains('application/xml') ||
        normalized.contains('text/xml')) {
      return 2;
    }
    if (normalized.contains('text/html')) {
      return 1;
    }
    return 0;
  }

  static bool _isSupportedAcquisition({
    required List<String> rels,
    required String type,
    required String? href,
  }) {
    final normalizedType = type.split(';').first.trim().toLowerCase();
    if (rels.any(
        (rel) => rel.startsWith(_acquisitionRelPrefix) || rel == _previewRel)) {
      if (normalizedType.isEmpty ||
          _mimeToExtension.containsKey(normalizedType)) {
        return true;
      }
    }

    if (_mimeToExtension.containsKey(normalizedType)) {
      return true;
    }

    if (href == null) {
      return false;
    }

    final ext = path
        .extension(Uri.parse(href).path)
        .replaceFirst('.', '')
        .toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  static String? _entrySummary(XmlElement entry) {
    final summary = _childText(entry, 'summary');
    if (summary != null && summary.trim().isNotEmpty) {
      return summary;
    }
    return _childText(entry, 'content');
  }

  static String _fallbackTitle(String? value, String fallback) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static String? _joinAuthors(dynamic rawAuthors) {
    if (rawAuthors == null) return null;

    final authors = <String>[];
    if (rawAuthors is String) {
      authors.add(rawAuthors);
    } else if (rawAuthors is Map) {
      final authorMap = Map<String, dynamic>.from(rawAuthors);
      final name = authorMap['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        authors.add(name);
      }
    } else if (rawAuthors is List) {
      for (final author in rawAuthors) {
        final name = _joinAuthors(author);
        if (name != null && name.isNotEmpty) {
          authors.add(name);
        }
      }
    }

    final cleaned = authors
        .map((author) => author.trim())
        .where((author) => author.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (cleaned.isEmpty) {
      return null;
    }
    return cleaned.join(', ');
  }

  static String? _resolveUrl(Uri baseUri, String? href) {
    if (href == null || href.trim().isEmpty) {
      return null;
    }
    return baseUri.resolve(href.trim()).toString();
  }

  static String _resolveTemplate(Uri baseUri, String template) {
    if (template.contains('://')) {
      return template;
    }

    const placeholderPrefix = '__ANX_OPDS_PLACEHOLDER_';
    final placeholders = <String>[];
    final masked = template.replaceAllMapped(
      RegExp(r'{[^}]+}'),
      (match) {
        final key = '$placeholderPrefix${placeholders.length}__';
        placeholders.add(match.group(0)!);
        return key;
      },
    );

    String resolved = baseUri.resolve(masked).toString();
    for (int i = 0; i < placeholders.length; i++) {
      resolved =
          resolved.replaceFirst('$placeholderPrefix${i}__', placeholders[i]);
    }
    return resolved;
  }

  static String? _cleanText(String? value) {
    if (value == null) return null;
    String current = value;
    for (int i = 0; i < 2; i++) {
      final text = html_parser
          .parseFragment(current)
          .text
          ?.replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text == null || text.isEmpty) {
        return null;
      }
      if (!RegExp(r'<[^>]+>').hasMatch(text)) {
        return text;
      }
      current = text;
    }
    return current.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<XmlElement> _childElements(XmlElement element, String localName) {
    return element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == localName)
        .toList(growable: false);
  }

  static String? _childText(XmlElement element, String localName) {
    for (final child in element.children.whereType<XmlElement>()) {
      if (child.name.local != localName) {
        continue;
      }
      return child.innerXml == child.innerText
          ? child.innerText
          : child.innerXml;
    }
    return null;
  }

  static List<String> _normalizeRels(dynamic relValue) {
    if (relValue == null) return const [];
    if (relValue is String) {
      return relValue
          .split(RegExp(r'\s+'))
          .map((rel) => rel.trim())
          .where((rel) => rel.isNotEmpty)
          .toList(growable: false);
    }
    if (relValue is List) {
      return relValue
          .map((rel) => rel.toString().trim())
          .where((rel) => rel.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static OpdsSearchLink? _findJsonSearchLink(
    List<Map<String, dynamic>> links,
    Uri baseUri,
  ) {
    for (final link in links) {
      final rels = _normalizeRels(link['rel']);
      if (!rels.contains('search')) {
        continue;
      }
      final href = _resolveUrl(baseUri, link['href']?.toString());
      if (href == null) {
        continue;
      }
      return OpdsSearchLink(
        url: href,
        type: link['type']?.toString().trim() ?? '',
        title: link['title']?.toString(),
      );
    }
    return null;
  }

  static OpdsSearchLink? _findAtomSearchLink(List<_ParsedLink> links) {
    for (final link in links) {
      if (link.href == null) {
        continue;
      }
      if (!link.rels.contains('search')) {
        continue;
      }
      return OpdsSearchLink(
        url: link.href!,
        type: link.type,
        title: link.title,
      );
    }
    return null;
  }
}

class _FetchedContent {
  const _FetchedContent({
    required this.body,
    required this.contentType,
    required this.responseUri,
  });

  final String body;
  final String? contentType;
  final Uri responseUri;
}

class _ParsedLink {
  const _ParsedLink({
    required this.rels,
    required this.href,
    required this.type,
    required this.title,
  });

  const _ParsedLink.empty()
      : rels = const [],
        href = null,
        type = '',
        title = null;

  final List<String> rels;
  final String? href;
  final String type;
  final String? title;

  factory _ParsedLink.fromXml(XmlElement element, Uri baseUri) {
    final href = element.getAttribute('href');
    return _ParsedLink(
      rels: OpdsParser._normalizeRels(element.getAttribute('rel')),
      href: href == null || href.trim().isEmpty
          ? null
          : baseUri.resolve(href.trim()).toString(),
      type: element.getAttribute('type')?.trim() ?? '',
      title: element.getAttribute('title')?.trim(),
    );
  }
}
