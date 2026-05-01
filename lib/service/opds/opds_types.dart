class OpdsFeed {
  const OpdsFeed({
    required this.title,
    this.subtitle,
    this.navigation = const [],
    this.publications = const [],
    this.search,
  });

  final String title;
  final String? subtitle;
  final List<OpdsNavigationEntry> navigation;
  final List<OpdsPublication> publications;
  final OpdsSearchLink? search;
}

class OpdsNavigationEntry {
  const OpdsNavigationEntry({
    required this.title,
    required this.url,
    this.summary,
  });

  final String title;
  final String url;
  final String? summary;
}

class OpdsPublication {
  const OpdsPublication({
    required this.title,
    this.author,
    this.summary,
    this.coverUrl,
    this.acquisitions = const [],
  });

  final String title;
  final String? author;
  final String? summary;
  final String? coverUrl;
  final List<OpdsAcquisition> acquisitions;

  bool get canImport => acquisitions.isNotEmpty;

  List<String> get formatLabels {
    return acquisitions
        .map((item) => item.formatLabel)
        .toSet()
        .toList(growable: false);
  }
}

class OpdsAcquisition {
  const OpdsAcquisition({
    required this.url,
    required this.type,
    this.rel,
    this.title,
  });

  final String url;
  final String type;
  final String? rel;
  final String? title;

  String get formatLabel {
    final normalized = type.split(';').first.trim().toLowerCase();

    if (normalized.contains('epub')) return 'EPUB';
    if (normalized.contains('pdf')) return 'PDF';
    if (normalized.contains('mobipocket') || normalized.contains('mobi')) {
      return 'MOBI';
    }
    if (normalized.contains('azw3') || normalized.contains('amazon')) {
      return 'AZW3';
    }
    if (normalized.contains('fb2') || normalized.contains('fictionbook')) {
      return 'FB2';
    }
    if (normalized.contains('text/plain')) return 'TXT';
    if (normalized.isNotEmpty) return normalized;
    return 'Book';
  }
}

class OpdsSearchLink {
  const OpdsSearchLink({
    required this.url,
    required this.type,
    this.title,
  });

  final String url;
  final String type;
  final String? title;

  bool get isTemplate => url.contains('{') && url.contains('}');

  bool get isOpenSearchDescription =>
      type.toLowerCase().contains('application/opensearchdescription+xml');
}

class OpdsSearch {
  const OpdsSearch({
    required this.template,
    this.title,
    this.description,
    this.defaults = const {},
  });

  final String template;
  final String? title;
  final String? description;
  final Map<String, String> defaults;
}
