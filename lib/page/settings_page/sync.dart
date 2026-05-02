import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/webdav/test_webdav.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';

const String _prefsBackupFileName = 'anx_shared_prefs.json';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                    L10n.of(context).commonNotSet),
                // enabled: Prefs().webdavStatus,
                onPressed: (context) async {
                  showWebdavDialog(context);
                }),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 20, 10),
                child: GestureDetector(
                  onTap: () async {
                    final l10n = L10n.of(context);
                    if (!await launchUrl(
                        Uri.parse('https://anx.anxcye.com/docs/sync/webdav'),
                        mode: LaunchMode.externalApplication)) {
                      AnxToast.show(l10n.commonFailed);
                    }
                  },
                  child: Text(
                    L10n.of(context).settingsNarrateClickForHelp,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                // value: Text(Prefs().syncDirection),
                enabled: Prefs().webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().onlySyncWhenWifi = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncState),
                description: Text(L10n.of(context).settingsSyncStateDesc),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().syncStateWithWebdav,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncStateWithWebdav = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncBookFiles),
                description: Text(L10n.of(context).settingsSyncBookFilesDesc),
                leading: const Icon(Icons.menu_book),
                initialValue: Prefs().syncBookFilesWithWebdav,
                enabled: Prefs().webdavStatus && Prefs().syncStateWithWebdav,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncBookFilesWithWebdav = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncKoReaderBridge),
                description:
                    Text(L10n.of(context).settingsSyncKoReaderBridgeDesc),
                leading: const Icon(Icons.import_export),
                initialValue: Prefs().koReaderSyncEnabled,
                enabled: Prefs().webdavStatus && Prefs().syncStateWithWebdav,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().koReaderSyncEnabled = value;
                  });
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncKoReaderServer),
                leading: const Icon(Icons.router),
                value: Text(Prefs().koReaderServerUrl.isEmpty
                    ? L10n.of(context).commonNotSet
                    : Prefs().koReaderServerUrl),
                enabled: Prefs().koReaderSyncEnabled,
                onPressed: (context) {
                  showKoReaderDialog(context);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncPreview),
                value: Text(Prefs().syncBookFilesWithWebdav
                    ? L10n.of(context).settingsSyncPreviewWithAssets
                    : L10n.of(context).settingsSyncPreviewWithoutAssets),
                leading: const Icon(Icons.preview),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showPreviewDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  exportData(context);
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> exportData(BuildContext context) async {
    AnxLog.info('exportData: start');
    if (!mounted) return;

    _showDataDialog(L10n.of(context).exporting);

    final File prefsBackupFile = await _createPrefsBackupFile();

    RootIsolateToken token = RootIsolateToken.instance!;
    final zipPath = await compute(createZipFile, {
      'token': token,
      'prefsBackupFilePath': prefsBackupFile.path,
    });

    final file = File(zipPath);
    SmartDialog.dismiss();
    if (await file.exists()) {
      // SaveFileDialogParams params = SaveFileDialogParams(
      //   sourceFilePath: file.path,
      //   mimeTypesFilter: ['application/zip'],
      // );
      // final filePath = await FlutterFileDialog.saveFile(params: params);
      String fileName =
          'AnxReader-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v3.zip';

      String? filePath = await saveFileToDownload(
          sourceFilePath: file.path,
          fileName: fileName,
          mimeType: 'application/zip');

      await file.delete();

      if (filePath != null) {
        AnxLog.info('exportData: Saved to: $filePath');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).exportTo(filePath));
      } else {
        AnxLog.info('exportData: Cancelled');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
      }
    }
  }

  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (!mounted) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null) {
      return;
    }

    String? filePath = result.files.single.path;
    if (filePath == null) {
      AnxLog.info('importData: cannot get file path');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    File zipFile = File(filePath);
    if (!await zipFile.exists()) {
      AnxLog.info('importData: zip file not found');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }
    _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);

    String pathSeparator = Platform.pathSeparator;

    Directory cacheDir = await getAnxTempDir();
    String cachePath = cacheDir.path;
    String extractPath = '$cachePath${pathSeparator}anx_reader_import';

    try {
      await Directory(extractPath).create(recursive: true);

      await compute(extractZipFile, {
        'zipFilePath': zipFile.path,
        'destinationPath': extractPath,
      });

      String docPath = await getAnxDocumentsPath();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}file'),
          getFileDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}cover'),
          getCoverDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}font'),
          getFontDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}bgimg'),
          getBgimgDir(path: docPath));

      DBHelper.close();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}databases'),
          await getAnxDataBasesDir());
      DBHelper().initDB();

      await _restorePrefsFromBackup(extractPath);

      AnxLog.info('importData: import success');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
    } catch (e) {
      AnxLog.info('importData: error while unzipping or copying files: $e');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
    } finally {
      SmartDialog.dismiss();
      await Directory(extractPath).delete(recursive: true);
    }
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    if (!source.existsSync()) {
      return;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    destination.createSync(recursive: true);
    source.listSync(recursive: false).forEach((entity) {
      final newPath = destination.path +
          Platform.pathSeparator +
          path.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory(newPath));
      }
    });
  }
}

Future<String> createZipFile(Map<String, dynamic> params) async {
  RootIsolateToken token = params['token'];
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final File prefsBackupFile = File(prefsBackupFilePath);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getAnxTempDir()).path}/AnxReader-Backup-$date.zip';
  final docPath = await getAnxDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath),
    getCoverDir(path: docPath),
    getFontDir(path: docPath),
    getBgimgDir(path: docPath),
    if (!AnxPlatform.isOhos) await getAnxDataBasesDir(),
    // await getAnxSharedPrefsDir(),
    // await getAnxShredPrefsFile(),
    prefsBackupFile,
  ];

  AnxLog.info('exportData: directoryList: $directoryList');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  if (AnxPlatform.isOhos) {
    final dbDir = await getAnxDataBasesDir();
    final dbFile = File('${dbDir.path}/app_database.db');
    if (await dbFile.exists()) {
      await encoder.addFile(dbFile, 'databases/app_database.db');
    }
  } else {
    final dbDir = await getAnxDataBasesDir();
    await encoder.addDirectory(dbDir);
  }

  for (final dir in directoryList) {
    if (dir is Directory) {
      await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }
  encoder.close();
  if (await prefsBackupFile.exists()) {
    await prefsBackupFile.delete();
  }
  return zipPath;
}

Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<File> _createPrefsBackupFile() async {
  final Directory tempDir = await getAnxTempDir();
  final File backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  final Map<String, dynamic> prefsMap = await Prefs().buildPrefsBackupMap();
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

Future<bool> _restorePrefsFromBackup(String extractPath) async {
  final File backupFile = File('$extractPath/$_prefsBackupFileName');
  if (!await backupFile.exists()) {
    return false;
  }
  try {
    final dynamic decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is Map<String, dynamic>) {
      await Prefs().applyPrefsBackupMap(decoded);
      return true;
    }
    AnxLog.info('importData: prefs backup has unexpected format');
  } catch (e) {
    AnxLog.info('importData: failed to restore prefs backup: $e');
  }
  return false;
}

void showWebdavDialog(BuildContext context) {
  final title = L10n.of(context).settingsSyncWebdav;
  // final prefs = Prefs().saveWebdavInfo;
  final webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  void applyNutstoreTemplate() {
    webdavUrlController.text = 'https://dav.jianguoyun.com/dav/';
  }

  showDialog(
    context: context,
    builder: (context) {
      final l10n = L10n.of(context);
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(l10n.settingsSyncWebdavObjectRootDesc),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsSyncWebdavNutstoreTemplateTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(l10n.settingsSyncWebdavNutstoreTemplateBody),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: applyNutstoreTemplate,
                    icon: const Icon(Icons.auto_fix_high),
                    label:
                        Text(l10n.settingsSyncWebdavApplyNutstoreTemplate),
                  ),
                ),
              ],
            ),
          ),
          buildTextField(
              l10n.settingsSyncWebdavUrl, webdavUrlController),
          buildTextField(
              l10n.settingsSyncWebdavUsername, webdavUsernameController),
          buildTextField(
              l10n.settingsSyncWebdavPassword, webdavPasswordController),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleFullTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(l10n.settingsSyncWebdavTestConnection),
              ),
              TextButton(
                onPressed: () {
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  Prefs().setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  SyncClientFactory.initializeCurrentClient();
                  Navigator.pop(context);
                },
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}

void showKoReaderDialog(BuildContext context) {
  final urlController = TextEditingController(text: Prefs().koReaderServerUrl);
  final usernameController =
      TextEditingController(text: Prefs().koReaderUsername);
  final passwordController =
      TextEditingController(text: Prefs().koReaderPassword);

  Widget buildTextField(
    String labelText,
    TextEditingController controller, {
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  showDialog(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: Text(L10n.of(dialogContext).settingsSyncKoReaderBridge),
        contentPadding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(L10n.of(dialogContext).settingsSyncKoReaderDialogDesc),
          ),
          buildTextField(L10n.of(dialogContext).settingsSyncKoReaderServerUrl,
              urlController),
          buildTextField(
              L10n.of(dialogContext).settingsSyncKoReaderServerUsername,
              usernameController),
          buildTextField(
              L10n.of(dialogContext).settingsSyncKoReaderServerPassword,
              passwordController,
              obscureText: true),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Prefs().koReaderServerUrl = urlController.text.trim();
                  Prefs().koReaderUsername = usernameController.text.trim();
                  Prefs().koReaderPassword = passwordController.text;
                  Navigator.pop(dialogContext);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
