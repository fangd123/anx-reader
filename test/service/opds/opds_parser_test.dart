import 'package:anx_reader/service/opds/opds_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpdsParser', () {
    test('parses Atom OPDS feeds with navigation and acquisitions', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dc="http://purl.org/dc/terms/">
  <title>Library</title>
  <subtitle>Fresh arrivals</subtitle>
  <entry>
    <title>Fiction</title>
    <summary>Browse fiction books</summary>
    <link rel="subsection" href="/fiction" type="application/atom+xml;profile=opds-catalog" />
  </entry>
  <entry>
    <title>Example Book</title>
    <author><name>Jane Doe</name></author>
    <summary>&lt;p&gt;A concise description.&lt;/p&gt;</summary>
    <link rel="http://opds-spec.org/image" href="/covers/example.jpg" type="image/jpeg" />
    <link rel="http://opds-spec.org/acquisition" href="/books/example.epub" type="application/epub+zip" />
  </entry>
</feed>
''';

      final feed = OpdsParser.parseFeed(
        body: xml,
        baseUri: Uri.parse('https://catalog.example/root'),
        contentType: 'application/atom+xml;profile=opds-catalog',
      );

      expect(feed.title, 'Library');
      expect(feed.subtitle, 'Fresh arrivals');
      expect(feed.navigation, hasLength(1));
      expect(feed.navigation.first.title, 'Fiction');
      expect(
        feed.navigation.first.url,
        'https://catalog.example/fiction',
      );

      expect(feed.publications, hasLength(1));
      final publication = feed.publications.first;
      expect(publication.title, 'Example Book');
      expect(publication.author, 'Jane Doe');
      expect(publication.summary, 'A concise description.');
      expect(
        publication.coverUrl,
        'https://catalog.example/covers/example.jpg',
      );
      expect(publication.acquisitions, hasLength(1));
      expect(
        publication.acquisitions.first.url,
        'https://catalog.example/books/example.epub',
      );
      expect(publication.acquisitions.first.formatLabel, 'EPUB');
    });

    test('parses OPDS 2 feeds with relative acquisitions', () {
      const jsonFeed = '''
{
  "metadata": {
    "title": "OPDS 2 Catalog",
    "subtitle": "<p>Updated weekly</p>"
  },
  "navigation": [
    {
      "title": "Recent",
      "href": "/recent",
      "summary": "Latest books"
    }
  ],
  "links": [
    {
      "rel": "search",
      "href": "/search{?searchTerms}",
      "type": "application/opds+json"
    }
  ],
  "publications": [
    {
      "metadata": {
        "title": "JSON Book",
        "description": "<p>Structured content</p>",
        "author": [
          {"name": "Alex Writer"}
        ]
      },
      "images": [
        {"href": "/covers/json-book.png"}
      ],
      "links": [
        {
          "rel": "http://opds-spec.org/acquisition",
          "href": "/download/json-book.epub",
          "type": "application/epub+zip"
        }
      ]
    }
  ]
}
''';

      final feed = OpdsParser.parseFeed(
        body: jsonFeed,
        baseUri: Uri.parse('https://reader.example/catalog'),
        contentType: 'application/opds+json',
      );

      expect(feed.title, 'OPDS 2 Catalog');
      expect(feed.subtitle, 'Updated weekly');
      expect(feed.navigation, hasLength(1));
      expect(feed.navigation.first.url, 'https://reader.example/recent');

      expect(feed.publications, hasLength(1));
      final publication = feed.publications.first;
      expect(publication.title, 'JSON Book');
      expect(publication.author, 'Alex Writer');
      expect(publication.summary, 'Structured content');
      expect(
        publication.coverUrl,
        'https://reader.example/covers/json-book.png',
      );
      expect(
        publication.acquisitions.first.url,
        'https://reader.example/download/json-book.epub',
      );
      expect(feed.search, isNotNull);
    });

    test('parses Atom search link and OpenSearch description', () {
      const feedXml = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Library</title>
  <link rel="search" href="/search.xml" type="application/opensearchdescription+xml" title="Search books" />
</feed>
''';

      final feed = OpdsParser.parseFeed(
        body: feedXml,
        baseUri: Uri.parse('https://catalog.example/root'),
        contentType: 'application/atom+xml;profile=opds-catalog',
      );

      expect(feed.search, isNotNull);
      expect(feed.search!.url, 'https://catalog.example/search.xml');
      expect(feed.search!.isOpenSearchDescription, isTrue);

      const openSearchXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>Catalog Search</ShortName>
  <Description>Find books</Description>
  <Url type="application/atom+xml;profile=opds-catalog" template="https://catalog.example/search?q={searchTerms}&amp;page={startPage?}" />
</OpenSearchDescription>
''';

      final search = OpdsParser.parseSearch(
        body: openSearchXml,
        baseUri: Uri.parse('https://catalog.example/search.xml'),
        contentType: 'application/opensearchdescription+xml',
      );

      expect(search.template,
          'https://catalog.example/search?q={searchTerms}&page={startPage?}');
      expect(search.title, 'Catalog Search');
      expect(search.description, 'Find books');
    });

    test('prefers OPDS-compatible search URLs over HTML results', () {
      const openSearchXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>Gutenberg</ShortName>
  <Url type="text/html" template="http://www.gutenberg.org/ebooks/search/?query={searchTerms}" />
  <Url type="application/atom+xml" template="http://m.gutenberg.org/ebooks/search.opds/?query={searchTerms}" />
</OpenSearchDescription>
''';

      final search = OpdsParser.parseSearch(
        body: openSearchXml,
        baseUri: Uri.parse('https://www.gutenberg.org/catalog/osd-books.xml'),
        contentType: 'application/opensearchdescription+xml',
      );

      expect(
        search.template,
        'http://m.gutenberg.org/ebooks/search.opds/?query={searchTerms}',
      );
    });
  });
}
