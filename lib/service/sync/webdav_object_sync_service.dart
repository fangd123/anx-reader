import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:collection/collection.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/sync/book_sync_state.dart';
import 'package:anx_reader/models/sync/sync_preview.dart';
import 'package:anx_reader/models/sync/webdav_sync_manifest.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/sync/local_sync_shadow_store.dart';
import 'package:anx_reader/service/sync/local_sync_snapshot_service.dart';
import 'package:anx_reader/service/sync/koreader_progress_bridge.dart';
import 'package:anx_reader/service/sync/sync_annotation_key.dart';
import 'package:anx_reader/service/sync/sync_json_file.dart';
import 'package:anx_reader/service/sync/sync_tombstone_store.dart';
import 'package:anx_reader/service/sync/webdav_object_store.dart';
import 'package:anx_reader/utils/get_path/sync_path.dart';
import 'package:path/path.dart' as p;

class WebdavObjectSyncResult {
  const WebdavObjectSyncResult({
    required this.preview,
    required this.conflicts,
  });

  final SyncPreviewState preview;
  final List<SyncConflict> conflicts;
}

class WebdavObjectSyncService {
  static const DeepCollectionEquality _deepCollectionEquality =
      DeepCollectionEquality();

  WebdavObjectSyncService(
    this._store, {
    KOReaderProgressBridge? koReaderBridge,
  }) : _koReaderBridge = koReaderBridge ?? KOReaderProgressBridge();

  final WebdavObjectStore _store;
  final KOReaderProgressBridge _koReaderBridge;

  Future<WebdavObjectSyncResult> sync({
    void Function(String phase, int current, int total)? onProgress,
  }) async {
    if (!Prefs().syncStateWithWebdav) {
      final preview = const SyncPreviewState(
        progress: SyncPreviewGroup(),
        annotations: SyncPreviewGroup(),
        chat: SyncPreviewGroup(),
        config: SyncPreviewGroup(),
        assets: SyncPreviewGroup(),
      );
      final previewFile = await getAnxSyncPreviewFile();
      await SyncJsonFile.writeJson(previewFile, preview.toJson());
      return const WebdavObjectSyncResult(
        preview: SyncPreviewState(
          progress: SyncPreviewGroup(),
          annotations: SyncPreviewGroup(),
          chat: SyncPreviewGroup(),
          config: SyncPreviewGroup(),
          assets: SyncPreviewGroup(),
        ),
        conflicts: <SyncConflict>[],
      );
    }

    await _store.ensureRoot();

    final localSnapshot = await LocalSyncSnapshotService.buildSnapshot();
    final remoteManifest = await _readManifest();
    final remoteBookMd5s = remoteManifest.books.isNotEmpty
        ? remoteManifest.books
        : await _store.listBookMd5s();
    final remoteSessionIds = remoteManifest.chats.isNotEmpty
        ? remoteManifest.chats
        : await _store.listAiSessionIds();

    final mergedBooks = <String, BookSyncState>{};
    final conflicts = <SyncConflict>[];

    final md5s = <String>{
      ...localSnapshot.books.keys,
      ...remoteBookMd5s,
    }.toList()
      ..sort();

    for (var i = 0; i < md5s.length; i++) {
      final md5 = md5s[i];
      onProgress?.call('books', i + 1, md5s.length);
      final localState = localSnapshot.books[md5];
      final shadow = await LocalSyncShadowStore.read(md5);
      final remoteState = await _readBookState(md5);
      final koReaderRemote = await _readKoReaderProgress(md5);
      final merged = _mergeBookState(
        md5: md5,
        local: localState,
        remote: remoteState,
        shadow: shadow?.state,
        koReaderRemote: koReaderRemote,
        conflicts: conflicts,
      );
      if (merged != null) {
        mergedBooks[md5] = merged;
      }
    }

    final mergedConfig = await _mergeConfig(localSnapshot.config, conflicts);
    final mergedChats =
        await _mergeChats(localSnapshot.chats, remoteSessionIds, conflicts);

    await _applyBooks(mergedBooks, onProgress: onProgress);
    await _applyChats(mergedChats);
    await Prefs().applySyncableConfigSnapshot(mergedConfig);

    if (Prefs().syncBookFilesWithWebdav) {
      await _syncAssets(mergedBooks, onProgress: onProgress);
    }

    final manifest = WebdavSyncManifest(
      version: 2,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      books: mergedBooks.keys.toList(growable: false)..sort(),
      devices: [Prefs().syncDeviceId],
      chats: mergedChats.map((entry) => entry.id).toList(growable: false),
    );

    await _store.writeJson(_store.manifestPath(), manifest.toJson());
    await _store.writeJson(
      _store.devicePath(Prefs().syncDeviceId),
      WebdavSyncDeviceRecord(
        deviceId: Prefs().syncDeviceId,
        deviceName: _deviceName(),
        platform: Platform.operatingSystem,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ).toJson(),
    );

    for (final entry in mergedBooks.entries) {
      await _store.writeJson(
          _store.bookStatePath(entry.key), entry.value.toJson());
      await LocalSyncShadowStore.write(
        SyncShadowState(
          md5: entry.key,
          lastSyncedAt: DateTime.now().toUtc().toIso8601String(),
          state: entry.value,
        ),
      );
      await _pushKoReaderProgress(entry.value);
    }

    for (final chat in mergedChats) {
      await _store.writeJson(_store.aiSessionPath(chat.id), chat.toJson());
    }

    await _store.writeJson(_store.globalConfigPath(), mergedConfig);

    final preview = SyncPreviewState(
      progress: SyncPreviewGroup(
        local: localSnapshot.books.length,
        remote: remoteBookMd5s.length,
        merged: mergedBooks.length,
      ),
      annotations: SyncPreviewGroup(
        local: localSnapshot.preview.annotations.local,
        remote: mergedBooks.values.fold<int>(
          0,
          (sum, state) =>
              sum + state.annotations.length + state.bookmarks.length,
        ),
        merged: mergedBooks.values.fold<int>(
          0,
          (sum, state) =>
              sum + state.annotations.length + state.bookmarks.length,
        ),
      ),
      chat: SyncPreviewGroup(
        local: localSnapshot.chats.length,
        remote: remoteSessionIds.length,
        merged: mergedChats.length,
      ),
      config: const SyncPreviewGroup(local: 1, remote: 1, merged: 1),
      assets: SyncPreviewGroup(
        local: localSnapshot.preview.assets.local,
        remote: mergedBooks.values.where((state) {
          return state.assetState.hasRemoteBook ||
              state.assetState.hasRemoteCover;
        }).length,
        merged: mergedBooks.values.where((state) {
          return state.assetState.localBookPath != null ||
              state.assetState.localCoverPath != null;
        }).length,
      ),
      warnings: conflicts.map((item) => item.message).toList(growable: false),
      hasRemoteData: remoteBookMd5s.isNotEmpty ||
          remoteSessionIds.isNotEmpty ||
          remoteManifest.updatedAt.isNotEmpty,
    );

    final previewFile = await getAnxSyncPreviewFile();
    await SyncJsonFile.writeJson(previewFile, preview.toJson());

    return WebdavObjectSyncResult(
      preview: preview,
      conflicts: conflicts,
    );
  }

  Future<WebdavSyncManifest> _readManifest() async {
    final json = await _store.readJson(_store.manifestPath());
    if (json == null) {
      return const WebdavSyncManifest();
    }
    return WebdavSyncManifest.fromJson(json);
  }

  Future<BookSyncState?> _readBookState(String md5) async {
    final json = await _store.readJson(_store.bookStatePath(md5));
    if (json == null) {
      return null;
    }
    return BookSyncState.fromJson(json);
  }

  BookSyncState? _mergeBookState({
    required String md5,
    required BookSyncState? local,
    required BookSyncState? remote,
    required BookSyncState? shadow,
    required KOReaderProgressRecord? koReaderRemote,
    required List<SyncConflict> conflicts,
  }) {
    if (local == null && remote == null) {
      return null;
    }
    if (local == null) {
      return koReaderRemote == null
          ? remote
          : remote?.copyWith(
              progress: _mergeProgress(
                md5: md5,
                local: remote.progress,
                remote: _koReaderBridge.mergeIntoProgress(
                  base: remote.progress,
                  remote: koReaderRemote,
                ),
                conflicts: conflicts,
              ),
              updatedAt: _latestIso(
                remote.updatedAt,
                koReaderRemote.timestamp,
              ),
            );
    }
    if (remote == null) {
      return koReaderRemote == null
          ? local
          : local.copyWith(
              progress: _mergeProgress(
                md5: md5,
                local: local.progress,
                remote: _koReaderBridge.mergeIntoProgress(
                  base: local.progress,
                  remote: koReaderRemote,
                ),
                conflicts: conflicts,
              ),
              updatedAt: _latestIso(
                local.updatedAt,
                koReaderRemote.timestamp,
              ),
            );
    }

    final progress = _mergeProgress(
      md5: md5,
      local: local.progress,
      remote: remote.progress,
      conflicts: conflicts,
    );
    final mergedProgress = koReaderRemote == null
        ? progress
        : _mergeProgress(
            md5: md5,
            local: progress,
            remote: _koReaderBridge.mergeIntoProgress(
              base: progress,
              remote: koReaderRemote,
            ),
            conflicts: conflicts,
          );

    final annotations = _mergeAnnotationSet(
      md5: md5,
      type: SyncConflictType.annotation,
      local: local.annotations,
      remote: remote.annotations,
      shadow: shadow?.annotations ?? const [],
      conflicts: conflicts,
    );
    final bookmarks = _mergeAnnotationSet(
      md5: md5,
      type: SyncConflictType.bookmark,
      local: local.bookmarks,
      remote: remote.bookmarks,
      shadow: shadow?.bookmarks ?? const [],
      conflicts: conflicts,
    );

    final mergedUpdatedAt = _latestIso(
      local.updatedAt,
      remote.updatedAt,
    );

    return remote.copyWith(
      title: local.title.isNotEmpty ? local.title : remote.title,
      author: local.author.isNotEmpty ? local.author : remote.author,
      fileExt: local.fileExt.isNotEmpty ? local.fileExt : remote.fileExt,
      updatedAt: mergedUpdatedAt,
      progress: mergedProgress,
      annotations: annotations,
      bookmarks: bookmarks,
      assetState: _mergeAssetState(local.assetState, remote.assetState),
      importHints: _mergeImportHints(local.importHints, remote.importHints),
    );
  }

  SyncProgressState _mergeProgress({
    required String md5,
    required SyncProgressState local,
    required SyncProgressState remote,
    required List<SyncConflict> conflicts,
  }) {
    final localTime = _parseIso(local.updatedAt);
    final remoteTime = _parseIso(remote.updatedAt);
    if (localTime == null) {
      return remote;
    }
    if (remoteTime == null) {
      return local;
    }
    final diff = localTime.difference(remoteTime).abs();
    if (diff.inSeconds <= 5) {
      if ((local.percentage - remote.percentage).abs() > 0.05) {
        conflicts.add(
          SyncConflict(
            type: SyncConflictType.progress,
            scope: md5,
            message: _localizedMessage(
              fallback: 'Progress conflict on $md5, using higher percentage.',
              builder: (l10n) => l10n.syncConflictProgressHigherPercentage(md5),
            ),
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt,
          ),
        );
      }
      return local.percentage >= remote.percentage ? local : remote;
    }
    final newer = localTime.isAfter(remoteTime) ? local : remote;
    final older = identical(newer, local) ? remote : local;
    if (newer.percentage + 0.15 < older.percentage) {
      conflicts.add(
        SyncConflict(
          type: SyncConflictType.progress,
          scope: md5,
          message: _localizedMessage(
            fallback:
                'Progress moved backwards on $md5, keeping newer timestamp.',
            builder: (l10n) => l10n.syncConflictProgressNewerTimestamp(md5),
          ),
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        ),
      );
    }
    return newer;
  }

  List<SyncAnnotationState> _mergeAnnotationSet({
    required String md5,
    required SyncConflictType type,
    required List<SyncAnnotationState> local,
    required List<SyncAnnotationState> remote,
    required List<SyncAnnotationState> shadow,
    required List<SyncConflict> conflicts,
  }) {
    final merged = <String, SyncAnnotationState>{};
    final keys = <String>{
      ...local.map((item) => item.key),
      ...remote.map((item) => item.key),
      ...shadow.map((item) => item.key),
    };

    final localMap = {for (final item in local) item.key: item};
    final remoteMap = {for (final item in remote) item.key: item};
    final shadowMap = {for (final item in shadow) item.key: item};

    for (final key in keys) {
      final localItem = localMap[key];
      final remoteItem = remoteMap[key];
      final shadowItem = shadowMap[key];
      final winner = _mergeAnnotationItem(
        md5: md5,
        type: type,
        local: localItem,
        remote: remoteItem,
        shadow: shadowItem,
        conflicts: conflicts,
      );
      if (winner != null) {
        merged[key] = winner;
      }
    }

    final result = merged.values.toList(growable: false)
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return result;
  }

  SyncAnnotationState? _mergeAnnotationItem({
    required String md5,
    required SyncConflictType type,
    required SyncAnnotationState? local,
    required SyncAnnotationState? remote,
    required SyncAnnotationState? shadow,
    required List<SyncConflict> conflicts,
  }) {
    if (local == null && remote == null) {
      return null;
    }
    if (local == null) {
      return remote;
    }
    if (remote == null) {
      return local;
    }

    final localTime =
        _parseIso(local.updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final remoteTime =
        _parseIso(remote.updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);

    if (local.deleted && remote.deleted) {
      return localTime.isAfter(remoteTime) ? local : remote;
    }

    if (local.deleted != remote.deleted) {
      final deleted = local.deleted ? local : remote;
      final active = local.deleted ? remote : local;
      final deletedTime = _parseIso(deleted.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final activeTime =
          _parseIso(active.updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (!deletedTime.isBefore(activeTime)) {
        return deleted;
      }
      conflicts.add(
        SyncConflict(
          type: type,
          scope: '$md5:${local.key}',
          message: _localizedMessage(
            fallback:
                'Deletion conflict on ${local.key}, keeping newer active item.',
            builder: (l10n) => l10n.syncConflictDeletionKeptActive(local.key),
          ),
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        ),
      );
      return active;
    }

    if (shadow != null &&
        shadow.updatedAt != local.updatedAt &&
        shadow.updatedAt != remote.updatedAt &&
        local.updatedAt != remote.updatedAt) {
      conflicts.add(
        SyncConflict(
          type: type,
          scope: '$md5:${local.key}',
          message: _localizedMessage(
            fallback: 'Concurrent edit on ${local.key}, keeping newer item.',
            builder: (l10n) => l10n.syncConflictConcurrentEdit(local.key),
          ),
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        ),
      );
    }

    return localTime.isAfter(remoteTime) ? local : remote;
  }

  BookAssetSyncState _mergeAssetState(
    BookAssetSyncState local,
    BookAssetSyncState remote,
  ) {
    return remote.copyWith(
      filesSyncEnabled: Prefs().syncBookFilesWithWebdav,
      hasRemoteBook: remote.hasRemoteBook || local.hasRemoteBook,
      hasRemoteCover: remote.hasRemoteCover || local.hasRemoteCover,
      localBookPath: local.localBookPath ?? remote.localBookPath,
      localCoverPath: local.localCoverPath ?? remote.localCoverPath,
      updatedAt: _latestIso(local.updatedAt, remote.updatedAt),
    );
  }

  BookImportHints _mergeImportHints(
      BookImportHints local, BookImportHints remote) {
    return remote.copyWith(
      opdsSourceId: local.opdsSourceId ?? remote.opdsSourceId,
      lastKnownFileName: local.lastKnownFileName ?? remote.lastKnownFileName,
      title: local.title ?? remote.title,
      author: local.author ?? remote.author,
    );
  }

  Future<Map<String, dynamic>> _mergeConfig(
    Map<String, dynamic> local,
    List<SyncConflict> conflicts,
  ) async {
    final remote = await _store.readJson(_store.globalConfigPath()) ?? {};
    if (remote.isEmpty) {
      return local;
    }
    final localValues = local['values'] is Map
        ? Map<String, dynamic>.from(local['values'] as Map)
        : Map<String, dynamic>.from(local);
    final remoteValues = remote['values'] is Map
        ? Map<String, dynamic>.from(remote['values'] as Map)
        : Map<String, dynamic>.from(remote);
    final localMeta = local['updatedAt'] is Map
        ? Map<String, String>.from(
            (local['updatedAt'] as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          )
        : Prefs().syncableConfigMeta;
    final remoteMeta = remote['updatedAt'] is Map
        ? Map<String, String>.from(
            (remote['updatedAt'] as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          )
        : const <String, String>{};

    final mergedValues = <String, dynamic>{};
    final mergedMeta = <String, String>{};
    final keys = <String>{...localValues.keys, ...remoteValues.keys};
    for (final key in keys) {
      final localValue = localValues[key];
      final remoteValue = remoteValues[key];
      final localTime = _parseIso(localMeta[key]);
      final remoteTime = _parseIso(remoteMeta[key]);
      if (remoteValue == null) {
        mergedValues[key] = localValue;
        if (localMeta[key] != null) {
          mergedMeta[key] = localMeta[key]!;
        }
        continue;
      }
      if (localValue == null) {
        mergedValues[key] = remoteValue;
        if (remoteMeta[key] != null) {
          mergedMeta[key] = remoteMeta[key]!;
        }
        continue;
      }

      final preferRemote = localTime == null ||
          (remoteTime != null && !remoteTime.isBefore(localTime));
      mergedValues[key] = preferRemote ? remoteValue : localValue;
      final chosenMeta = preferRemote ? remoteMeta[key] : localMeta[key];
      if (chosenMeta != null) {
        mergedMeta[key] = chosenMeta;
      }
      if (!_deepCollectionEquality.equals(remoteValue, localValue) &&
          localTime != null &&
          remoteTime != null) {
        conflicts.add(
          SyncConflict(
            type: SyncConflictType.config,
            scope: key,
            message: _localizedMessage(
              fallback:
                  'Config conflict on $key, keeping ${preferRemote ? 'remote' : 'local'} value.',
              builder: (l10n) => preferRemote
                  ? l10n.syncConflictConfigKeepRemote(key)
                  : l10n.syncConflictConfigKeepLocal(key),
            ),
            localUpdatedAt: localMeta[key],
            remoteUpdatedAt: remoteMeta[key],
          ),
        );
      }
    }
    return {
      'values': mergedValues,
      'updatedAt': mergedMeta,
    };
  }

  Future<List<AiChatHistoryEntry>> _mergeChats(
    List<AiChatHistoryEntry> localChats,
    List<String> remoteSessionIds,
    List<SyncConflict> conflicts,
  ) async {
    final merged = {for (final item in localChats) item.id: item};
    for (final sessionId in remoteSessionIds) {
      final json = await _store.readJson(_store.aiSessionPath(sessionId));
      if (json == null) {
        continue;
      }
      final remote = AiChatHistoryEntry.fromJson(json);
      final existing = merged[sessionId];
      if (existing == null || remote.updatedAt > existing.updatedAt) {
        merged[sessionId] = remote;
      } else if (existing.updatedAt != remote.updatedAt) {
        conflicts.add(
          SyncConflict(
            type: SyncConflictType.chat,
            scope: sessionId,
            message: _localizedMessage(
              fallback:
                  'Chat conflict on $sessionId, keeping newer session.',
              builder: (l10n) => l10n.syncConflictChatNewerSession(sessionId),
            ),
            localUpdatedAt: existing.updatedAt.toString(),
            remoteUpdatedAt: remote.updatedAt.toString(),
          ),
        );
      }
    }
    final result = merged.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> _applyBooks(
    Map<String, BookSyncState> books, {
    void Function(String phase, int current, int total)? onProgress,
  }) async {
    final allBooks = await bookDao.selectAllBooks();
    final booksByMd5 = <String, Book>{
      for (final book in allBooks)
        if ((book.md5 ?? '').isNotEmpty) book.md5!: book,
    };
    final tombstones = await SyncTombstoneStore.readAll();

    var index = 0;
    for (final entry in books.entries) {
      index++;
      onProgress?.call('apply', index, books.length);
      final md5 = entry.key;
      final state = entry.value;
      final existing = booksByMd5[md5];
      if (existing == null) {
        await _createCloudOnlyBook(state);
      } else {
        await _applyBookState(existing, state, tombstones);
      }
    }
  }

  Future<void> _createCloudOnlyBook(BookSyncState state) async {
    final existing = await bookDao.getBookByMd5(state.md5);
    if (existing != null) {
      await _applyBookState(existing, state, const {});
      return;
    }
    final fallbackExt = state.fileExt.isEmpty ? 'epub' : state.fileExt;
    final fileName = state.importHints.lastKnownFileName ??
        '${state.title.isEmpty ? state.md5 : state.title}.$fallbackExt';
    final book = Book(
      id: -1,
      title: state.title.isEmpty ? fileName : state.title,
      coverPath: 'cover/${state.md5}.png',
      filePath: 'file/$fileName',
      lastReadPosition: state.progress.position,
      readingPercentage: state.progress.percentage,
      author: state.author,
      isDeleted: false,
      rating: 0,
      md5: state.md5,
      createTime: DateTime.now(),
      updateTime: _parseIso(state.updatedAt) ?? DateTime.now(),
    );
    await bookDao.insertBook(book);
  }

  Future<void> _applyBookState(
    Book existing,
    BookSyncState state,
    Map<String, SyncAnnotationTombstone> tombstones,
  ) async {
    final updatedBook = existing.copyWith(
      title: state.title.isNotEmpty ? state.title : existing.title,
      author: state.author.isNotEmpty ? state.author : existing.author,
      lastReadPosition: state.progress.position,
      readingPercentage: state.progress.percentage,
      updateTime: _parseIso(state.updatedAt) ?? DateTime.now(),
      md5: state.md5,
    );
    await bookDao.updateBook(updatedBook);

    final currentNotes = await bookNoteDao.selectBookNotesByBookId(existing.id);
    final byKey = <String, BookNote>{
      for (final note in currentNotes)
        SyncAnnotationKeyBuilder.build(note.type, note.cfi): note,
    };

    for (final item in [...state.annotations, ...state.bookmarks]) {
      final current = byKey[item.key];
      if (item.deleted) {
        if (current?.id != null) {
          await bookNoteDao.deleteBookNoteById(current!.id!);
        }
        await SyncTombstoneStore.markDeleted(
          SyncAnnotationTombstone(
            md5: state.md5,
            key: item.key,
            type: item.type,
            cfi: item.cfi,
            deletedAt: item.updatedAt,
          ),
        );
        continue;
      }

      final note = BookNote(
        id: current?.id,
        bookId: existing.id,
        content: item.content,
        cfi: item.cfi,
        chapter: item.chapter,
        type: item.type,
        color: item.color,
        readerNote: item.readerNote,
        createTime:
            _parseIso(item.createdAt ?? item.updatedAt) ?? DateTime.now(),
        updateTime: _parseIso(item.updatedAt) ?? DateTime.now(),
      );
      await bookNoteDao.save(note);
      if (tombstones.containsKey(item.key)) {
        await SyncTombstoneStore.remove(item.key);
      }
    }
  }

  Future<void> _applyChats(List<AiChatHistoryEntry> chats) async {
    await AiHistoryStore.clear();
    for (final chat in chats) {
      await AiHistoryStore.upsertEntry(chat);
    }
  }

  Future<void> _syncAssets(
    Map<String, BookSyncState> books, {
    void Function(String phase, int current, int total)? onProgress,
  }) async {
    var index = 0;
    for (final entry in books.entries) {
      index++;
      onProgress?.call('assets', index, books.length);
      final state = entry.value;
      final book = await bookDao.getBookByMd5(entry.key);
      if (book == null) {
        continue;
      }

      final ext = state.fileExt.isEmpty
          ? p.extension(book.filePath).replaceFirst('.', '')
          : state.fileExt;
      final remoteBookPath = _store.bookAssetPath(entry.key, ext);
      final remoteCoverPath = _store.coverAssetPath(
        entry.key,
        p.extension(book.coverPath).replaceFirst('.', '').ifEmpty('png'),
      );

      final localBookFile = File(book.fileFullPath);
      if (localBookFile.existsSync()) {
        final remoteProps = await _store.readProps(remoteBookPath);
        if (remoteProps == null) {
          await _store.uploadAsset(localBookFile.path, remoteBookPath);
        }
      } else {
        final remoteProps = await _store.readProps(remoteBookPath);
        if (remoteProps != null) {
          await _store.downloadAsset(remoteBookPath, localBookFile.path);
        }
      }

      final localCoverFile = File(book.coverFullPath);
      if (localCoverFile.existsSync()) {
        final remoteProps = await _store.readProps(remoteCoverPath);
        if (remoteProps == null) {
          await _store.uploadAsset(localCoverFile.path, remoteCoverPath);
        }
      } else {
        final remoteProps = await _store.readProps(remoteCoverPath);
        if (remoteProps != null) {
          await _store.downloadAsset(remoteCoverPath, localCoverFile.path);
        }
      }
    }
  }

  DateTime? _parseIso(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  String _latestIso(String a, String b) {
    final aTime = _parseIso(a);
    final bTime = _parseIso(b);
    if (aTime == null) {
      return b;
    }
    if (bTime == null) {
      return a;
    }
    return aTime.isAfter(bTime) ? a : b;
  }

  String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'anx-device';
    }
  }

  Future<KOReaderProgressRecord?> _readKoReaderProgress(String md5) async {
    if (!_koReaderBridge.isConfigured) {
      return null;
    }
    try {
      return await _koReaderBridge.fetchProgress(md5);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pushKoReaderProgress(BookSyncState state) async {
    if (!_koReaderBridge.isConfigured) {
      return;
    }
    try {
      await _koReaderBridge.pushProgress(state, deviceName: _deviceName());
    } catch (_) {}
  }

  String _localizedMessage({
    required String fallback,
    required String Function(L10n l10n) builder,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return fallback;
    }
    return builder(L10n.of(context));
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
