import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String tagLeaders = '!@#^&~+=\\|';
const int maxBackups = 5;

/// Regex matching #when[YYYY-MM-DD H:MM:SS AM/PM]
final RegExp whenTagRegex = RegExp(r'#when\[\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}:\d{2}\s+[AP]M\]');

/// Parse the datetime value inside a #when[...] tag.
DateTime? parseWhenDateTime(String tag) {
  final match = RegExp(r'#when\[(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(AM|PM)\]').firstMatch(tag);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  var hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final period = match.group(7)!;
  if (period == 'AM' && hour == 12) hour = 0;
  if (period == 'PM' && hour != 12) hour += 12;
  return DateTime(year, month, day, hour, minute, second);
}

/// Format a DateTime as a #when[...] tag string.
String formatWhenTag(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  var hour = dt.hour;
  final period = hour >= 12 ? 'PM' : 'AM';
  if (hour == 0) {
    hour = 12;
  } else if (hour > 12) {
    hour -= 12;
  }
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  return '#when[$y-$m-$d $hour:$min:$sec $period]';
}

/// Extract all #when dates from entry text.
List<DateTime> extractWhenDates(String text) {
  final dates = <DateTime>[];
  for (final match in whenTagRegex.allMatches(text)) {
    final dt = parseWhenDateTime(match.group(0)!);
    if (dt != null) dates.add(dt);
  }
  return dates;
}

// Default time windows in minutes
const int defaultAroundNowWindow = 60;
const int defaultRelatedEntriesWindow = 30;
const int defaultGroupingWindow = 5;

Future<File> _getSettingsFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan_settings.txt');
}

Future<Map<String, int>> loadTimeSettings() async {
  try {
    final file = await _getSettingsFile();
    if (await file.exists()) {
      final contents = await file.readAsString();
      final lines = contents.split('\n');
      final settings = <String, int>{};
      for (final line in lines) {
        if (line.contains('=')) {
          final parts = line.split('=');
          settings[parts[0]] = int.tryParse(parts[1]) ?? 0;
        }
      }
      return {
        'aroundNow': settings['aroundNow'] ?? defaultAroundNowWindow,
        'relatedEntries': settings['relatedEntries'] ?? defaultRelatedEntriesWindow,
        'groupingWindow': settings['groupingWindow'] ?? defaultGroupingWindow,
      };
    }
  } catch (e) {
    // Silently fail
  }
  return {
    'aroundNow': defaultAroundNowWindow,
    'relatedEntries': defaultRelatedEntriesWindow,
    'groupingWindow': defaultGroupingWindow,
  };
}

Future<void> saveTimeSettings(int aroundNow, int relatedEntries, [int? groupingWindow]) async {
  try {
    final file = await _getSettingsFile();
    final gw = groupingWindow ?? defaultGroupingWindow;
    await file.writeAsString('aroundNow=$aroundNow\nrelatedEntries=$relatedEntries\ngroupingWindow=$gw');
  } catch (e) {
    // Silently fail
  }
}

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

const _backupChannel = MethodChannel('com.example.bunyan/backup');

/// Request Android to back up app data to Google cloud.
/// This notifies the OS that data has changed and should be backed up soon.
Future<bool> requestGoogleBackup() async {
  try {
    if (!Platform.isAndroid) return false;
    final result = await _backupChannel.invokeMethod('requestBackup');
    return result == true;
  } catch (e) {
    return false;
  }
}
