import 'dart:io' as io;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/models/sync/sync_preview.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/sync_json_file.dart';
import 'package:anx_reader/service/sync/webdav_object_store.dart';
import 'package:anx_reader/service/sync/webdav_object_sync_service.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/sync_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync.g.dart';

@Riverpod(keepAlive: true)
class Sync extends _$Sync {
  static final Sync _instance = Sync._internal();

  factory Sync() => _instance;

  Sync._internal();

  @override
  SyncStateModel build() {
    return const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '',
    );
  }

  SyncClientBase? get _syncClient {
    if (SyncClientFactory.currentClient == null) {
      SyncClientFactory.initializeCurrentClient();
    }
    return SyncClientFactory.currentClient;
  }

  void changeState(SyncStateModel next) {
    state = next;
  }

  Future<void> init() async {
    final client = _syncClient;
    if (client == null) {
      return;
    }
    AnxLog.info('${client.protocolName}: init');
  }

  Future<bool> shouldSync() async {
    if (!Prefs().webdavStatus) {
      return false;
    }

    if (Prefs().onlySyncWhenWifi &&
        !(await Connectivity().checkConnectivity())
            .contains(ConnectivityResult.wifi)) {
      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavOnlyWifi);
      }
      return false;
    }

    return true;
  }

  Future<void> syncData(
    SyncDirection direction,
    WidgetRef? widgetRef, {
    SyncTrigger trigger = SyncTrigger.auto,
  }) async {
    if (!Prefs().syncStateWithWebdav) {
      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).syncStateDisabled);
      }
      return;
    }
    final client = _syncClient;
    if (client == null) {
      return;
    }

    if (trigger == SyncTrigger.auto && !Prefs().autoSync) {
      return;
    }

    if (!(await shouldSync())) {
      return;
    }

    if (state.isSyncing) {
      AnxLog.info('Sync already in progress, skipping');
      return;
    }

    try {
      await client.ping();
    } catch (e) {
      AnxLog.severe('WebDAV ping failed: $e');
      return;
    }

    changeState(state.copyWith(
      direction: direction,
      isSyncing: true,
      count: 0,
      total: 0,
      fileName: 'sync',
    ));

    if (Prefs().syncCompletedToast) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncing);
    }

    final service = WebdavObjectSyncService(WebdavObjectStore(client));

    try {
      final result = await service.sync(
        onProgress: (phase, current, total) {
          changeState(state.copyWith(
            direction: direction == SyncDirection.download
                ? SyncDirection.download
                : SyncDirection.upload,
            isSyncing: true,
            fileName: phase,
            count: current,
            total: total,
          ));
        },
      );

      imageCache.clear();
      imageCache.clearLiveImages();

      try {
        widgetRef?.read(bookListProvider.notifier).refresh();
        widgetRef?.read(groupDaoProvider.notifier).refresh();
        widgetRef?.read(syncStatusProvider.notifier).refresh();
        widgetRef?.read(aiHistoryProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh providers: $e');
      }

      if (result.conflicts.isNotEmpty) {
        await _showConflicts(result);
      }

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncComplete);
      }
    } catch (e, s) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusWebdavCheckNetwork,
        );
      } else {
        AnxToast.show(
          L10n.of(navigatorKey.currentContext!).syncFailedWithError(
            e.toString(),
          ),
        );
      }
      AnxLog.severe('Sync failed\n$e\n$s');
    } finally {
      changeState(state.copyWith(isSyncing: false));
    }
  }

  Future<List<String>> listRemoteBookFiles() async {
    final client = _syncClient;
    if (client == null) {
      return [];
    }
    final store = WebdavObjectStore(client);
    final md5s = await store.listBookMd5s();
    return md5s;
  }

  Future<RemoteFile?> readRemoteBookAsset(String md5, String extension) async {
    final client = _syncClient;
    if (client == null) {
      return null;
    }
    final store = WebdavObjectStore(client);
    return store.readProps(store.bookAssetPath(md5, extension));
  }

  Future<void> downloadBook(Book book) async {
    final md5 = book.md5?.trim();
    if (md5 == null || md5.isEmpty) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusBookNotFoundRemote);
      return;
    }
    final extension = book.filePath.split('.').last.isEmpty
        ? 'epub'
        : book.filePath.split('.').last;
    try {
      await _downloadBookAsset(book, md5, extension);
    } catch (_) {}
  }

  Future<void> releaseBook(Book book) async {
    final md5 = book.md5?.trim();
    if (md5 == null || md5.isEmpty) {
      return;
    }

    if (!Prefs().syncBookFilesWithWebdav) {
      final file = io.File(book.fileFullPath);
      if (await file.exists()) {
        await file.delete();
      }
      ref.read(syncStatusProvider.notifier).refresh();
      return;
    }

    final extension = book.filePath.split('.').last.isEmpty
        ? 'epub'
        : book.filePath.split('.').last;
    final client = _syncClient;
    if (client == null) {
      return;
    }
    final store = WebdavObjectStore(client);
    final remotePath = store.bookAssetPath(md5, extension);
    final localFile = io.File(book.fileFullPath);

    if (await localFile.exists()) {
      final remoteProps = await store.readProps(remotePath);
      if (remoteProps == null) {
        await uploadFile(localFile.path, remotePath);
      }
      await localFile.delete();
    }

    ref.read(syncStatusProvider.notifier).refresh();
  }

  Future<void> downloadMultipleBooks(List<int> bookIds) async {
    var successCount = 0;
    var failCount = 0;
    for (final bookId in bookIds) {
      try {
        final book = await bookDao.selectBookById(bookId);
        await downloadBook(book);
        successCount++;
      } catch (e) {
        AnxLog.severe('Failed to download book $bookId: $e');
        failCount++;
      }
    }
    AnxToast.show(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, [
    bool replace = true,
  ]) async {
    final client = _syncClient;
    if (client == null) {
      return;
    }
    changeState(state.copyWith(
      direction: SyncDirection.upload,
      fileName: localPath.split('/').last,
    ));
    ref.read(syncStatusProvider.notifier).addUploading(remotePath);
    await client.uploadFile(
      localPath,
      remotePath,
      replace: replace,
      onProgress: (sent, total) {
        changeState(state.copyWith(isSyncing: true, count: sent, total: total));
      },
    );
    ref.read(syncStatusProvider.notifier).removeUploading(remotePath);
    changeState(state.copyWith(isSyncing: false));
  }

  Future<void> downloadFile(String remotePath, String localPath) async {
    final client = _syncClient;
    if (client == null) {
      return;
    }
    changeState(state.copyWith(
      direction: SyncDirection.download,
      fileName: remotePath.split('/').last,
    ));
    ref.read(syncStatusProvider.notifier).addDownloading(remotePath);
    await client.downloadFile(
      remotePath,
      localPath,
      onProgress: (received, total) {
        changeState(
          state.copyWith(isSyncing: true, count: received, total: total),
        );
      },
    );
    ref.read(syncStatusProvider.notifier).removeDownloading(remotePath);
    changeState(state.copyWith(isSyncing: false));
  }

  Future<SyncPreviewState?> readPreview() async {
    final file = await getAnxSyncPreviewFile();
    final json = await SyncJsonFile.readMap(file);
    if (json == null) {
      return null;
    }
    return SyncPreviewState.fromJson(json);
  }

  Future<void> showPreviewDialog() async {
    final preview = await readPreview();
    final context = navigatorKey.currentContext;
    if (context == null || preview == null) {
      return;
    }
    await SmartDialog.show(
      builder: (_) => AlertDialog(
        title: Text(L10n.of(context).settingsSyncPreview),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).syncPreviewProgress(
                  preview.progress.merged,
                  preview.progress.local,
                  preview.progress.remote,
                ),
              ),
              Text(
                L10n.of(context).syncPreviewAnnotations(
                  preview.annotations.merged,
                  preview.annotations.local,
                  preview.annotations.remote,
                ),
              ),
              Text(
                L10n.of(context).syncPreviewChat(
                  preview.chat.merged,
                  preview.chat.local,
                  preview.chat.remote,
                ),
              ),
              Text(
                L10n.of(context).syncPreviewConfig(
                  preview.config.merged,
                  preview.config.local,
                  preview.config.remote,
                ),
              ),
              Text(
                L10n.of(context).syncPreviewAssets(
                  preview.assets.merged,
                  preview.assets.local,
                  preview.assets.remote,
                ),
              ),
              if (preview.warnings.isNotEmpty) const SizedBox(height: 12),
              if (preview.warnings.isNotEmpty)
                Text(preview.warnings.join('\n')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadBookAsset(
    Book book,
    String md5,
    String extension,
  ) async {
    final client = _syncClient;
    if (client == null) {
      return;
    }
    final store = WebdavObjectStore(client);
    final remotePath = store.bookAssetPath(md5, extension);
    final localPath = getBasePath(book.filePath);
    await downloadFile(remotePath, localPath);
  }

  Future<void> _showConflicts(WebdavObjectSyncResult result) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    await SmartDialog.show(
      builder: (_) => AlertDialog(
        title: Text(L10n.of(context).commonAttention),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              result.conflicts.map((item) => item.message).join('\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }
}
