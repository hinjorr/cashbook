import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/drive_backup.dart';
import '../services/local_backup.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final _drive = DriveBackup(context.read<AppState>().prefs);
  bool _busy = false;

  Future<void> _run(Future<String?> Function() job) async {
    setState(() => _busy = true);
    try {
      final msg = await job();
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text('All current data on this phone will be replaced by the backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restoreFromDrive() async {
    final s = context.read<AppState>();
    List<DriveBackupFile> files = [];
    await _run(() async {
      files = await _drive.listBackups();
      return files.isEmpty ? 'No backups found on Google Drive.' : null;
    });
    if (files.isEmpty || !mounted) return;
    final f = await showModalBottomSheet<DriveBackupFile>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in files)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(f.modified == null ? f.name : DateFormat('d MMM yyyy, h:mm a').format(f.modified!)),
                subtitle: Text(f.size == null ? f.name : '${(f.size! / 1024).toStringAsFixed(1)} KB'),
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (f == null || !await _confirmRestore()) return;
    await _run(() async {
      await _drive.restore(s.db, f);
      await s.changed();
      return 'Backup restored.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final email = _drive.email;
    final last = _drive.lastBackup;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            const ListTile(title: Text('Google Drive', style: TextStyle(fontWeight: FontWeight.w600))),
            if (email == null)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Connect Google Drive'),
                subtitle: const Text('Backups go to a "Cashbook Backups" folder in your Drive.'),
                onTap: () => _run(() async {
                  final e = await _drive.connect();
                  return 'Connected as $e';
                }),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(email),
                subtitle: Text(last == null ? 'No backup yet' : 'Last backup ${DateFormat('d MMM yyyy, h:mm a').format(last)}'),
                trailing: TextButton(
                  onPressed: () => _run(() async {
                    await _drive.disconnect();
                    return 'Disconnected.';
                  }),
                  child: const Text('Sign out'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Back up now'),
                onTap: () => _run(() async {
                  await _drive.backupNow(s.db);
                  return 'Backed up to Google Drive.';
                }),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('Restore from Google Drive'),
                onTap: _restoreFromDrive,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.schedule),
                title: const Text('Automatic daily backup'),
                subtitle: const Text('Backs up when you open the app, at most once a day. Keeps the latest 15.'),
                value: _drive.autoBackup,
                onChanged: (v) async {
                  await _drive.setAutoBackup(v);
                  setState(() {});
                },
              ),
            ],
            const Divider(),
            const ListTile(title: Text('Backup file', style: TextStyle(fontWeight: FontWeight.w600))),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export backup file'),
              subtitle: const Text('Save or send a .json backup'),
              onTap: () => _run(() async {
                await shareBackupFile(s.db);
                return null;
              }),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from file'),
              onTap: () async {
                if (!await _confirmRestore()) return;
                await _run(() async {
                  if (!await restoreBackupFile(s.db)) return null;
                  await s.changed();
                  return 'Backup restored.';
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
