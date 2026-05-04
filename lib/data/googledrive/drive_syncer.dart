import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/googledrive/drive_client.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/main.dart' show scaffoldMessengerKey;

final log = Logger('DriveSyncer');

/// Stato corrente del sync Drive — osservabile dalla UI
enum DriveSyncStatus { idle, syncing, done, error }

class DriveSyncState {
  static final status = ValueNotifier<DriveSyncStatus>(DriveSyncStatus.idle);
  static final lastSync = ValueNotifier<DateTime?>(null);
  static final lastError = ValueNotifier<String?>(null);

  static void _set(DriveSyncStatus s, {String? error}) {
    status.value = s;
    if (error != null) lastError.value = error;
    if (s == DriveSyncStatus.done) {
      lastSync.value = DateTime.now();
      lastError.value = null;
    }
  }
}

/// Syncs local files to/from Google Drive.
///
/// Files are stored in Drive under:
///   appDataFolder/notes/<relative_path>
///
/// No encryption — files are stored as-is, which lets the webapp read them.
class DriveSyncer {
  DriveSyncer._();

  static bool _running = false;

  /// Starts a full sync cycle (upload local changes, download remote changes).
  /// Safe to call multiple times — only one cycle runs at a time.
  static Future<void> sync() async {
    if (_running) return;
    _running = true;
    DriveSyncState._set(DriveSyncStatus.syncing);
    try {
      final api = await DriveClient.getDriveApi();
      if (api == null) {
        log.info('sync: not logged in, skipping');
        DriveSyncState._set(DriveSyncStatus.idle);
        return;
      }
      log.info('sync: starting');
      await Future.wait([
        _uploadLocalChanges(api),
        _downloadRemoteChanges(api),
      ]);
      log.info('sync: done');
      DriveSyncState._set(DriveSyncStatus.done);
    } catch (e, st) {
      log.severe('sync: error: $e', e, st);
      DriveSyncState._set(DriveSyncStatus.error, error: e.toString());
    } finally {
      _running = false;
    }
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  static Future<void> _uploadLocalChanges(drive.DriveApi api) async {
    final allFiles = await FileManager.getAllFiles(
      includeExtensions: true,
      includeAssets: true,
    );

    log.info('_uploadLocalChanges: found ${allFiles.length} files: $allFiles');

    for (final relativePath in allFiles) {
      try {
        await uploadFile(api, relativePath);
      } catch (e, st) {
        log.warning('uploadLocalChanges: failed for $relativePath: $e', e, st);
      }
    }
  }

  /// Uploads a single file to Drive.
  /// [relativePath] must start with '/'.
  static Future<void> uploadFile(
    drive.DriveApi api,
    String relativePath,
  ) async {
    final localFile = FileManager.getFile(relativePath);
    if (!localFile.existsSync()) {
      // File was deleted — remove from Drive too
      await _deleteRemoteFile(api, relativePath);
      return;
    }

    final bytes = await localFile.readAsBytes();
    final remoteId = await _getRemoteFileId(api, relativePath);
    final lastModified = localFile.lastModifiedSync();

    final metadata = drive.File()
      ..name = _remoteNameFromPath(relativePath)
      ..modifiedTime = lastModified;

    final media = drive.Media(Stream.value(bytes), bytes.length);

    if (remoteId == null) {
      // Create new file
      metadata.parents = ['appDataFolder'];
      metadata.appProperties = {'path': relativePath};
      await api.files.create(metadata, uploadMedia: media);
      log.fine('uploaded (new): $relativePath');
    } else {
      // Check if local is newer before uploading
      final remoteFile = await _getRemoteFileMeta(api, remoteId);
      final remoteModified = remoteFile?.modifiedTime;
      final lastModifiedUtc = lastModified.toUtc();
      final remoteModifiedUtc = remoteModified?.toUtc();
      if (remoteModifiedUtc != null &&
          remoteModifiedUtc.isAfter(lastModifiedUtc) &&
          remoteModifiedUtc.difference(lastModifiedUtc).abs() >
              const Duration(seconds: 5)) {
        log.fine('skipping upload (remote newer): $relativePath');
        return;
      }
      await api.files.update(metadata, remoteId, uploadMedia: media);
      log.fine('uploaded (updated): $relativePath');
    }
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  static Future<void> _downloadRemoteChanges(drive.DriveApi api) async {
    final remoteFiles = await _listRemoteFiles(api);
    log.info(
      '_downloadRemoteChanges: found ${remoteFiles.length} remote files',
    );

    for (final remoteFile in remoteFiles) {
      final relativePath = remoteFile.appProperties?['path'];
      if (relativePath == null) continue;

      try {
        await _downloadFileIfNewer(api, remoteFile, relativePath);
      } catch (e, st) {
        log.warning(
          'downloadRemoteChanges: failed for $relativePath: $e',
          e,
          st,
        );
      }
    }
  }

  static Future<void> _downloadFileIfNewer(
    drive.DriveApi api,
    drive.File remoteFile,
    String relativePath,
  ) async {
    final localFile = FileManager.getFile(relativePath);
    final remoteModified = remoteFile.modifiedTime;
    log.info(
      '_downloadFileIfNewer: $relativePath'
      ' remote=${remoteModified?.toUtc()}'
      ' local=${localFile.existsSync() ? localFile.lastModifiedSync().toUtc() : "missing"}',
    );

    if (remoteModified != null && localFile.existsSync()) {
      // Confronta sempre in UTC per evitare problemi di timezone
      final localModified = localFile.lastModifiedSync().toUtc();
      final remoteModifiedUtc = remoteModified.toUtc();
      final diff = remoteModifiedUtc.difference(localModified);
      if (diff.abs() < const Duration(seconds: 5)) return;
      if (localModified.isAfter(remoteModifiedUtc)) {
        log.fine('skipping download (local newer): $relativePath');
        return;
      }
    }

    // Download
    final media =
        await api.files.get(
              remoteFile.id!,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final bytes = await _collectStream(media.stream);
    await FileManager.writeFile(
      relativePath,
      bytes,
      alsoUpload: false,
      awaitWrite: true,
      lastModified: remoteModified?.toUtc(),
    );
    log.fine('downloaded: $relativePath');
    _notifyFileUpdated(relativePath);
  }

  // ─── Delete ────────────────────────────────────────────────────────────────

  static Future<void> _deleteRemoteFile(
    drive.DriveApi api,
    String relativePath,
  ) async {
    final remoteId = await _getRemoteFileId(api, relativePath);
    if (remoteId == null) return;
    await api.files.delete(remoteId);
    log.fine('deleted remote: $relativePath');
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Lists all files stored in appDataFolder.
  static Future<List<drive.File>> _listRemoteFiles(drive.DriveApi api) async {
    final result = <drive.File>[];
    String? pageToken;

    do {
      final fileList = await api.files.list(
        spaces: 'appDataFolder',
        pageToken: pageToken,
        $fields: 'nextPageToken, files(id, name, modifiedTime, appProperties)',
      );
      result.addAll(fileList.files ?? []);
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);

    return result;
  }

  /// Returns the Drive file ID for [relativePath], or null if not found.
  static Future<String?> _getRemoteFileId(
    drive.DriveApi api,
    String relativePath,
  ) async {
    final escapedPath = relativePath.replaceAll("'", "\\'");
    final fileList = await api.files.list(
      spaces: 'appDataFolder',
      q: "appProperties has { key='path' and value='$escapedPath' }",
      $fields: 'files(id)',
    );
    return fileList.files?.firstOrNull?.id;
  }

  static Future<drive.File?> _getRemoteFileMeta(
    drive.DriveApi api,
    String fileId,
  ) async {
    try {
      return await api.files.get(fileId, $fields: 'id, modifiedTime')
          as drive.File;
    } catch (e) {
      return null;
    }
  }

  /// Converts a relative path like '/folder/note.sbn2' to a flat file name
  /// safe for Drive: 'folder__note.sbn2'.
  /// The actual path is stored in appProperties, this is just for readability.
  static String _remoteNameFromPath(String relativePath) {
    return relativePath.replaceAll(RegExp(r'^/'), '').replaceAll('/', '__');
  }

  static Future<Uint8List> _collectStream(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  /// Shows a SnackBar when a note is updated from Drive.
  static void _notifyFileUpdated(String relativePath) {
    // Only notify for main note files, not previews or assets
    if (!relativePath.endsWith('.sbn2')) return;
    if (relativePath.endsWith('.sbn2.p')) return;

    // Get a friendly name from the path
    final name = relativePath.split('/').last.replaceAll('.sbn2', '');

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Updated: $name'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          onPressed: () =>
              scaffoldMessengerKey.currentState?.hideCurrentSnackBar(),
        ),
      ),
    );
  }
}

/// Enqueues a file for upload after a short debounce delay.
/// Called by FileManager after every write.
class DriveUploadQueue {
  static final _pending = <String>{};
  static Timer? _timer;

  static void enqueue(String relativePath) {
    if (!stows.driveLoggedIn) return;
    _pending.add(relativePath);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), _flush);
  }

  static Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final toUpload = Set<String>.from(_pending);
    _pending.clear();

    final api = await DriveClient.getDriveApi();
    if (api == null) return;

    for (final path in toUpload) {
      try {
        await DriveSyncer.uploadFile(api, path);
      } catch (e, st) {
        log.warning('DriveUploadQueue: failed for $path: $e', e, st);
      }
    }
  }
}
