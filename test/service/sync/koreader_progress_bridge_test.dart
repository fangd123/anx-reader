import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:anx_reader/service/sync/koreader_progress_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeIntoProgress prefers xpointer and timestamp', () {
    final bridge = KOReaderProgressBridge();
    final merged = bridge.mergeIntoProgress(
      base: const SyncProgressState(
        position: '',
        percentage: 0.1,
        updatedAt: '2024-01-01T00:00:00.000Z',
      ),
      remote: const KOReaderProgressRecord(
        md5: 'book-md5',
        percentage: 0.75,
        xpointer: '/body/DocFragment[12]',
        timestamp: '2024-01-02T00:00:00.000Z',
        device: 'koreader',
      ),
    );

    expect(merged.position, '/body/DocFragment[12]');
    expect(merged.percentage, 0.75);
    expect(merged.updatedAt, '2024-01-02T00:00:00.000Z');
    expect(merged.deviceId, 'koreader');
  });

  test('resolveReaderFraction reads normalized fraction', () {
    final bridge = KOReaderProgressBridge();
    final fraction = bridge.resolveReaderFraction(
      const SyncProgressState(fraction: '0.42'),
    );

    expect(fraction, '0.42');
  });
}
