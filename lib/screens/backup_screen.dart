import 'package:flutter/material.dart';
import 'dart:io';

import '../utils.dart';

class BackupScreen extends StatefulWidget {
  final VoidCallback onRestore;

  const BackupScreen({
    super.key,
    required this.onRestore,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<File> _backups = [];
  Map<String, int> _entryCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final backups = await getBackups();
    final files = backups.cast<File>();

    // Load entry counts for each backup
    final counts = <String, int>{};
    for (final file in files) {
      counts[file.path] = await getBackupEntryCount(file);
    }

    setState(() {
      _backups = files;
      _entryCounts = counts;
      _isLoading = false;
    });
  }

  Future<void> _createManualBackup() async {
    await createBackup();
    await _loadBackups();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created')),
      );
    }
  }

  Future<void> _restoreBackup(File backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore Backup'),
        content: Text(
          'This will replace all current data with the backup from ${getBackupDisplayName(backup.path)}.\n\nThis cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await restoreBackup(backup);
      widget.onRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup restored')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _deleteBackup(File backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Backup'),
        content: Text('Delete backup from ${getBackupDisplayName(backup.path)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await deleteBackup(backup);
      await _loadBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backups'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _createManualBackup,
            tooltip: 'Create Backup Now',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Auto-backup runs daily. Last $maxBackups backups are kept.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.cloud_upload),
                    label: Text('Google Backup'),
                    onPressed: () async {
                      final ok = await requestGoogleBackup();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok
                              ? 'Backup requested — Android will sync shortly'
                              : 'Not available on this platform')),
                        );
                      }
                    },
                  ),
                ),
                Divider(),
                Expanded(
                  child: _backups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.backup, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No backups yet',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Backups are created automatically\nthe first time you open the app each day.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _createManualBackup,
                                icon: Icon(Icons.backup),
                                label: Text('Create Backup Now'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            final displayName = getBackupDisplayName(backup.path);
                            final entryCount = _entryCounts[backup.path] ?? 0;

                            return ListTile(
                              leading: Icon(Icons.backup),
                              title: Text(displayName),
                              subtitle: Text('$entryCount entries'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.restore, color: Colors.blue),
                                    onPressed: () => _restoreBackup(backup),
                                    tooltip: 'Restore',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _deleteBackup(backup),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
