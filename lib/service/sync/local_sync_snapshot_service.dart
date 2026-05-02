import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:anx_reader/models/sync/sync_preview.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/sync/sync_annotation_key.dart';
import 'package:anx_reader/service/sync/sync_tombstone_store.dart';
import 'package:path/path.dart' as p;

class LocalSyncSnapshot {
  const LocalSyncSnapshot({
    required this.books,
    required this.config,
    required this.chats,
    required this.preview,
  });

  final Map<String, BookSyncState> books;
  final Map<String, dynamic> config;
  final List<AiChatHistoryEntry> chats;
  final SyncPreviewState preview;
}

class LocalSyncSnapshotService {
  const LocalSyncSnapshotService._();

  static Future<LocalSyncSnapshot> buildSnapshot() async {
    await _ensureBookMd5s();
    final books = await bookDao.selectAllBooks();
    final tombstones = await SyncTombstoneStore.readAll();
    final states = <String, BookSyncState>{};

    for (final book in books) {
      final md5 = book.md5?.trim() ?? '';
      if (md5.isEmpty) {
        continue;
      }
      states[md5] = await _buildBookState(book, tombstones);
    }

    final chats = await AiHistoryStore.readHistory();
    final config = Prefs().buildSyncableConfigSnapshot();
    final preview = SyncPreviewState(
      progress: SyncPreviewGroup(local: states.length, remote: 0, merged: 0),
      annotations: SyncPreviewGroup(
        local: states.values.fold<int>(
          0,
          (sum, state) => sum + state.annotations.length + state.bookmarks.length,
        ),
        remote: 0,
        merged: 0,
      ),
      chat: SyncPreviewGroup(local: chats.length, remote: 0, merged: 0),
      config: const SyncPreviewGroup(local: 1, remote: 0, merged: 0),
      assets: SyncPreviewGroup(
        local: states.values.where((state) {
          return state.assetState.localBookPath != null ||
              state.assetState.localCoverPath != null;
        }).length,
        remote: 0,
        merged: 0,
      ),
      hasRemoteData: false,
    );

    return LocalSyncSnapshot(
      books: states,
      config: config,
      chats: chats,
      preview: preview,
    );
  }

  static Future<BookSyncState> _buildBookState(
    Book book,
    Map<String, SyncAnnotationTombstone> tombstones,
  ) async {
    final notes = await bookNoteDao.selectBookNotesByBookId(book.id);
    final annotations = <SyncAnnotationState>[];
    final bookmarks = <SyncAnnotationState>[];

    for (final note in notes) {
      final state = _noteToSyncState(book, note);
      if (note.type == 'bookmark') {
        bookmarks.add(state);
      } else {
        annotations.add(state);
      }
    }

    final relatedTombstones = tombstones.values.where((tombstone) {
      return tombstone.md5 == book.md5 &&
          !annotations.any((item) => item.key == tombstone.key) &&
          !bookmarks.any((item) => item.key == tombstone.key);
    });

    for (final tombstone in relatedTombstones) {
      final state = SyncAnnotationState(
        key: tombstone.key,
        type: tombstone.type,
        cfi: tombstone.cfi,
        updatedAt: tombstone.deletedAt,
        deleted: true,
      );
      if (tombstone.type == 'bookmark') {
        bookmarks.add(state);
      } else {
        annotations.add(state);
      }
    }

    final fileExt = p.extension(book.filePath).replaceFirst('.', '').toLowerCase();
    final localBook = File(book.fileFullPath);
    final localCover = File(book.coverFullPath);

    return BookSyncState(
      md5: book.md5!,
      title: book.title,
      author: book.author,
      fileExt: fileExt,
      updatedAt: book.updateTime.toUtc().toIso8601String(),
      progress: SyncProgressState(
        position: book.lastReadPosition,
        percentage: book.readingPercentage,
        deviceId: Prefs().syncDeviceId,
        updatedAt: book.updateTime.toUtc().toIso8601String(),
      ),
      annotations: annotations,
      bookmarks: bookmarks,
      assetState: BookAssetSyncState(
        filesSyncEnabled: Prefs().syncBookFilesWithWebdav,
        hasRemoteBook: false,
        hasRemoteCover: false,
        localBookPath: localBook.existsSync() ? book.filePath : null,
        localCoverPath: localCover.existsSync() ? book.coverPath : null,
        updatedAt: book.updateTime.toUtc().toIso8601String(),
      ),
      importHints: BookImportHints(
        title: book.title,
        author: book.author,
        lastKnownFileName: p.basename(book.filePath),
      ),
    );
  }

  static SyncAnnotationState _noteToSyncState(Book book, BookNote note) {
    final createTime = note.createTime?.toUtc().toIso8601String();
    return SyncAnnotationState(
      key: SyncAnnotationKeyBuilder.build(note.type, note.cfi),
      type: note.type,
      cfi: note.cfi,
      content: note.content,
      chapter: note.chapter,
      color: note.color,
      readerNote: note.readerNote,
      createdAt: createTime,
      updatedAt: note.updateTime.toUtc().toIso8601String(),
    );
  }

  static Future<void> _ensureBookMd5s() async {
    final missing = await bookDao.getBooksWithoutMd5();
    for (final book in missing) {
      if (!File(book.fileFullPath).existsSync()) {
        continue;
      }
      final md5 = await MD5Service.calculateFileMd5(book.fileFullPath);
      if (md5 != null && md5.isNotEmpty) {
        await bookDao.updateBookMd5(book.id, md5);
      }
    }
  }
}
