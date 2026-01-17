import 'dart:io';
import 'package:path_provider/path_provider.dart';

const String tagLeaders = '!@#^&~+=\\|';
const int maxBackups = 5;

Future<File> getFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan.csv');
}

Future<Directory> getBackupDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  final backupDir = Directory('${directory.path}/bunyan_backups');
  if (!await backupDir.exists()) {
    await backupDir.create(recursive: true);
  }
  return backupDir;
}

Future<File> getLastBackupDateFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan_last_backup.txt');
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

Future<bool> shouldBackupToday() async {
  final lastBackupFile = await getLastBackupDateFile();
  if (!await lastBackupFile.exists()) {
    return true;
  }
  final lastBackupDate = await lastBackupFile.readAsString();
  final today = _formatDate(DateTime.now());
  return lastBackupDate.trim() != today;
}

Future<void> createBackup() async {
  final sourceFile = await getFile();
  if (!await sourceFile.exists()) {
    return; // Nothing to backup
  }

  final backupDir = await getBackupDirectory();
  final today = _formatDate(DateTime.now());
  final backupFile = File('${backupDir.path}/bunyan_backup_$today.csv');

  await sourceFile.copy(backupFile.path);

  // Update last backup date
  final lastBackupFile = await getLastBackupDateFile();
  await lastBackupFile.writeAsString(today);

  // Rotate old backups
  await rotateBackups();
}

Future<void> rotateBackups() async {
  final backupDir = await getBackupDirectory();
  final files = await backupDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.csv'))
      .cast<File>()
      .toList();

  // Sort by name (which includes date) descending - newest first
  files.sort((a, b) => b.path.compareTo(a.path));

  // Delete old backups beyond the limit
  if (files.length > maxBackups) {
    for (var i = maxBackups; i < files.length; i++) {
      await files[i].delete();
    }
  }
}

Future<List<FileSystemEntity>> getBackups() async {
  final backupDir = await getBackupDirectory();
  if (!await backupDir.exists()) {
    return [];
  }

  final files = await backupDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.csv'))
      .toList();

  // Sort by name descending - newest first
  files.sort((a, b) => b.path.compareTo(a.path));
  return files;
}

Future<void> restoreBackup(File backupFile) async {
  final targetFile = await getFile();
  await backupFile.copy(targetFile.path);
}

Future<void> deleteBackup(File backupFile) async {
  if (await backupFile.exists()) {
    await backupFile.delete();
  }
}

String getBackupDisplayName(String path) {
  // Extract date from filename like "bunyan_backup_2024-01-15.csv"
  final filename = path.split('/').last.split('\\').last;
  final match = RegExp(r'bunyan_backup_(\d{4}-\d{2}-\d{2})\.csv').firstMatch(filename);
  if (match != null) {
    return match.group(1)!;
  }
  return filename;
}

Future<int> getBackupEntryCount(File backupFile) async {
  if (!await backupFile.exists()) return 0;
  final contents = await backupFile.readAsString();
  return contents.split('\n').where((line) => line.isNotEmpty).length;
}
