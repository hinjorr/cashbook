import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';

/// Writes a JSON backup to a temp file and opens the share sheet, so the
/// user can save it to Files, email it, send it on WhatsApp, etc.
Future<void> shareBackupFile(AppDatabase db) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final file = File(p.join(dir.path, 'cashbook-backup-$stamp.json'));
  await file.writeAsString(jsonEncode(await db.exportData()));
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/json')],
    subject: 'Cashbook backup',
  ));
}

/// Lets the user pick a backup JSON file and restores it. Returns false if
/// the picker was cancelled.
Future<bool> restoreBackupFile(AppDatabase db) async {
  final picked = await FilePicker.pickFile(type: FileType.any);
  if (picked == null) return false;
  final text = utf8.decode(await picked.xFile.readAsBytes());
  await db.importData(jsonDecode(text) as Map<String, Object?>);
  return true;
}
