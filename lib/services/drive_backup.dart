import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';

/// Web OAuth client ID from Google Cloud, passed at build time with
/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`.
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

const _scopes = [drive.DriveApi.driveFileScope];
const _folderName = 'Cashbook Backups';
const _filePrefix = 'cashbook-backup-';
const _keepBackups = 15;

class DriveBackupFile {
  final String id;
  final String name;
  final DateTime? modified;
  final int? size;

  const DriveBackupFile(this.id, this.name, this.modified, this.size);
}

/// Backs the database up to the user's Google Drive, into a visible
/// "Cashbook Backups" folder. Uses the drive.file scope, so the app can only
/// see files it created itself.
class DriveBackup {
  DriveBackup(this.prefs);

  final SharedPreferences prefs;
  static bool _initialized = false;

  String? get email => prefs.getString('drive_email');
  bool get autoBackup => prefs.getBool('drive_auto') ?? true;
  Future<void> setAutoBackup(bool v) => prefs.setBool('drive_auto', v);

  DateTime? get lastBackup {
    final ms = prefs.getInt('drive_last');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
  }

  /// Interactive sign-in. Shows Google's account picker and consent screen.
  Future<String> connect() async {
    await _init();
    final account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    await account.authorizationClient.authorizeScopes(_scopes);
    await prefs.setString('drive_email', account.email);
    return account.email;
  }

  Future<void> disconnect() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    await prefs.remove('drive_email');
  }

  /// Gets a Drive client. When [interactive] is false this never shows UI and
  /// returns null if the user would have to sign in again.
  Future<drive.DriveApi?> _api({required bool interactive}) async {
    await _init();
    GoogleSignInAccount? account;
    final light = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (light != null) account = await light;
    if (account == null) {
      if (!interactive) return null;
      account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    }
    var auth = await account.authorizationClient.authorizationForScopes(_scopes);
    if (auth == null) {
      if (!interactive) return null;
      auth = await account.authorizationClient.authorizeScopes(_scopes);
    }
    await prefs.setString('drive_email', account.email);
    return drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  Future<String> _folderId(drive.DriveApi api) async {
    final found = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' and name = '$_folderName' and trashed = false",
      $fields: 'files(id)',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;
    final created = await api.files.create(
      drive.File(name: _folderName, mimeType: 'application/vnd.google-apps.folder'),
      $fields: 'id',
    );
    return created.id!;
  }

  /// Uploads a full backup and prunes old ones. Returns the file name.
  Future<String> backupNow(AppDatabase db, {bool interactive = true}) async {
    final api = await _api(interactive: interactive);
    if (api == null) throw StateError('Not signed in to Google Drive.');
    final folder = await _folderId(api);
    final bytes = utf8.encode(jsonEncode(await db.exportData()));
    final now = DateTime.now();
    final stamp = now.toIso8601String().replaceAll(':', '-').split('.').first;
    final name = '$_filePrefix$stamp.json';
    await api.files.create(
      drive.File(name: name, parents: [folder], mimeType: 'application/json'),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json'),
    );
    await prefs.setInt('drive_last', now.millisecondsSinceEpoch);

    final all = await _list(api);
    for (final old in all.skip(_keepBackups)) {
      await api.files.delete(old.id);
    }
    return name;
  }

  Future<List<DriveBackupFile>> _list(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "name contains '$_filePrefix' and trashed = false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,name,modifiedTime,size)',
      pageSize: 100,
    );
    return [
      for (final f in res.files ?? <drive.File>[])
        DriveBackupFile(f.id!, f.name ?? '', f.modifiedTime?.toLocal(), int.tryParse(f.size ?? '')),
    ];
  }

  Future<List<DriveBackupFile>> listBackups() async {
    final api = await _api(interactive: true);
    return _list(api!);
  }

  Future<void> restore(AppDatabase db, DriveBackupFile file) async {
    final api = await _api(interactive: true);
    final media = await api!.files.get(
      file.id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    await db.importData(data);
  }

  /// Called on app start: if auto backup is on and the last backup is older
  /// than a day, back up silently. Failures are ignored.
  Future<void> autoBackupIfDue(AppDatabase db) async {
    if (email == null || !autoBackup) return;
    final last = lastBackup;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    try {
      await backupNow(db, interactive: false);
    } catch (_) {
      // Silent: the user can always back up manually from the Backup screen.
    }
  }
}
