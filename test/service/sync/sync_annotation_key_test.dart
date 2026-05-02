import 'package:anx_reader/service/sync/sync_annotation_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds stable annotation key from type and cfi', () {
    final key1 = SyncAnnotationKeyBuilder.build('bookmark', 'epubcfi(/6/2)');
    final key2 = SyncAnnotationKeyBuilder.build('bookmark', 'epubcfi(/6/2)');
    final key3 = SyncAnnotationKeyBuilder.build('highlight', 'epubcfi(/6/2)');

    expect(key1, key2);
    expect(key1, isNot(key3));
    expect(key1, hasLength(40));
  });

  test('creates tombstone with md5 and timestamp', () {
    final tombstone = SyncAnnotationKeyBuilder.tombstone(
      md5: 'abc',
      type: 'bookmark',
      cfi: 'epubcfi(/6/4)',
      deletedAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
    );

    expect(tombstone.md5, 'abc');
    expect(tombstone.type, 'bookmark');
    expect(tombstone.cfi, 'epubcfi(/6/4)');
    expect(tombstone.deletedAt, '2024-01-02T03:04:05.000Z');
  });
}
