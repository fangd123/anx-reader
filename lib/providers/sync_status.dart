import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_status.g.dart';

@Riverpod(keepAlive: true)
class SyncStatus extends _$SyncStatus {
  List<Book> allBooksInBookShelf = [];

  @override
  Future<SyncStatusModel> build() async {
    allBooksInBookShelf = await bookDao.selectNotDeleteBooks();
    final remoteMd5s = await _listRemoteMd5s();
    final localOnly = <int>[];
    final remoteOnly = <int>[];
    final both = <int>[];
    final nonExistent = <int>[];

    for (final book in allBooksInBookShelf) {
      final hasLocalFile = File(book.fileFullPath).existsSync();
      final md5 = book.md5?.trim() ?? '';
      final hasRemote = md5.isNotEmpty && remoteMd5s.contains(md5);

      if (hasLocalFile && hasRemote) {
        both.add(book.id);
      } else if (hasLocalFile) {
        localOnly.add(book.id);
      } else if (hasRemote) {
        remoteOnly.add(book.id);
      } else {
        nonExistent.add(book.id);
      }
    }

    final syncState = ref.read(syncProvider);
    final isSyncing = syncState.isSyncing;
    final activeBookId = await pathToBookId(syncState.fileName);

    final downloading = isSyncing &&
            syncState.direction.name == 'download' &&
            activeBookId != null
        ? [activeBookId]
        : <int>[];

    final uploading = isSyncing &&
            syncState.direction.name == 'upload' &&
            activeBookId != null
        ? [activeBookId]
        : <int>[];

    return SyncStatusModel(
      localOnly: localOnly,
      remoteOnly: remoteOnly,
      both: both,
      nonExistent: nonExistent,
      downloading: downloading,
      uploading: uploading,
    );
  }

  Future<void> refresh() async {
    state = AsyncData(await build());
  }

  Future<List<String>> _listRemoteMd5s() async {
    try {
      return await ref.read(syncProvider.notifier).listRemoteBookFiles();
    } catch (e) {
      AnxLog.info('Failed to list remote files: $e');
      return [];
    }
  }

  Future<int?> pathToBookId(String filePath) async {
    if (filePath.isEmpty || filePath == 'sync') {
      return null;
    }

    for (final book in allBooksInBookShelf) {
      final md5 = book.md5?.trim() ?? '';
      if (filePath.contains(book.filePath) ||
          filePath.contains(book.coverPath) ||
          (md5.isNotEmpty && filePath.contains(md5))) {
        return book.id;
      }
    }

    allBooksInBookShelf = await bookDao.selectNotDeleteBooks();

    for (final book in allBooksInBookShelf) {
      final md5 = book.md5?.trim() ?? '';
      if (filePath.contains(book.filePath) ||
          filePath.contains(book.coverPath) ||
          (md5.isNotEmpty && filePath.contains(md5))) {
        return book.id;
      }
    }

    return null;
  }

  bool isCover(String filePath) {
    return filePath.contains('/cover/') || filePath.contains('cover.');
  }

  Future<void> addDownloading(String filePath) async {
    if (isCover(filePath)) {
      return;
    }
    final bookId = await pathToBookId(filePath);
    if (bookId == null || state.value == null) {
      return;
    }
    state = AsyncData(
      state.value!.copyWith(downloading: [...state.value!.downloading, bookId]),
    );
  }

  Future<void> addUploading(String filePath) async {
    if (isCover(filePath)) {
      return;
    }
    final bookId = await pathToBookId(filePath);
    if (bookId == null || state.value == null) {
      return;
    }
    state = AsyncData(
      state.value!.copyWith(uploading: [...state.value!.uploading, bookId]),
    );
  }

  Future<void> removeDownloading(String filePath) async {
    if (isCover(filePath)) {
      return;
    }
    final bookId = await pathToBookId(filePath);
    if (bookId == null || state.value == null) {
      return;
    }
    state = AsyncData(
      state.value!.copyWith(
        downloading:
            state.value!.downloading.where((item) => item != bookId).toList(),
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> removeUploading(String filePath) async {
    if (isCover(filePath)) {
      return;
    }
    final bookId = await pathToBookId(filePath);
    if (bookId == null || state.value == null) {
      return;
    }
    state = AsyncData(
      state.value!.copyWith(
        uploading:
            state.value!.uploading.where((item) => item != bookId).toList(),
      ),
    );
    ref.invalidateSelf();
  }
}
