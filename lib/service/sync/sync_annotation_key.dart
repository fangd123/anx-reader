import 'dart:convert';

import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:crypto/crypto.dart';

class SyncAnnotationKeyBuilder {
  const SyncAnnotationKeyBuilder._();

  static String build(String type, String cfi) {
    final digest = sha1.convert(utf8.encode('$type:$cfi'));
    return digest.toString();
  }

  static SyncAnnotationTombstone tombstone({
    required String md5,
    required String type,
    required String cfi,
    DateTime? deletedAt,
  }) {
    final timestamp = (deletedAt ?? DateTime.now()).toUtc().toIso8601String();
    return SyncAnnotationTombstone(
      md5: md5,
      key: build(type, cfi),
      type: type,
      cfi: cfi,
      deletedAt: timestamp,
    );
  }
}
