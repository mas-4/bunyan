import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../models.dart';
import '../utils.dart';
import 'edit_entry_screen.dart';
import 'hotbar_settings_screen.dart';
import 'backup_screen.dart';
import 'time_suggestions_screen.dart';

class WordLoggerHome extends StatefulWidget {
  const WordLoggerHome({super.key});

  @override
  WordLoggerHomeState createState() => WordLoggerHomeState();
}

class WordLoggerHomeState extends State<WordLoggerHome> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<WordEntry> _entries = [];
  List<WordEntry> _displayEntries = [];
  bool _isLoading = true;
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  bool _showAllMatches = false;
  bool _hasSearchText = false;

  List<String> _hotbarTags = [];

  bool _bulkEditMode = false;
  final Set<int> _selectedIndices = {};

  // Frequency map: word -> count
  Map<String, int> get _wordFrequencies {
    final counts = <String, int>{};
    for (final entry in _entries) {
      counts[entry.word] = (counts[entry.word] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _controller.addListener(_filterEntries);
  }

  Future<void> _initializeApp() async {
    // Check for daily backup first
    await _checkDailyBackup();
    // Then load data
    await _loadEntries();
    await _loadHotbarTags();
  }

  Future<void> _checkDailyBackup() async {
    try {
      if (await shouldBackupToday()) {
        await createBackup();
      }
    } catch (e) {
      // Silently fail - backup is best-effort
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _enterBulkEditMode(WordEntry entry) {
    final actualIndex = _entries.indexOf(entry);
    setState(() {
      _bulkEditMode = true;
      _selectedIndices.add(actualIndex);
    });
  }

  void _exitBulkEditMode() {
    setState(() {
      _bulkEditMode = false;
      _selectedIndices.clear();
    });
  }

  Future<void> _bulkEditDateTime() async {
    if (_selectedIndices.isEmpty) return;

    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );

    if (time == null || !mounted) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    try {
      final indicesToUpdate = _selectedIndices.toList()..sort();

      for (int index in indicesToUpdate.reversed) {
        final entry = _entries[index];
        _entries[index] = WordEntry(word: entry.word, timestamp: newDateTime);
      }

      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed.map((entry) => entry.toCsv()).join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError("${_selectedIndices.length} entries updated");
      _exitBulkEditMode();
    } catch (e) {
      _showError('Error updating entries: $e');
    }
  }

  Future<void> _combineEntries() async {
    if (_selectedIndices.length < 2) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Combine Entries'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a name for the combined entry:'),
            SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'e.g., fruit',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text('Combine'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final selectedEntries = _selectedIndices.map((index) => _entries[index]).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final entryWords = selectedEntries.map((entry) => entry.word.replaceAll(':', ',')).join(', ');
      final combinedText = '$name: $entryWords';

      final latestTimestamp = selectedEntries
          .map((entry) => entry.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final combinedEntry = WordEntry(
        word: combinedText,
        timestamp: latestTimestamp,
      );

      final indicesToRemove = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      for (int index in indicesToRemove) {
        _entries.removeAt(index);
      }

      _entries.add(combinedEntry);
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed.map((entry) => entry.toCsv()).join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError("${_selectedIndices.length} entries combined into '$name'");
      _exitBulkEditMode();
    } catch (e) {
      _showError('Error combining entries: $e');
    }
  }

  Future<void> _bulkDuplicateEntries() async {
    if (_selectedIndices.isEmpty) return;

    try {
      final selectedEntries = _selectedIndices.map((index) => _entries[index]).toList();
      final now = DateTime.now();

      final duplicates = selectedEntries
          .map((entry) => WordEntry(word: entry.word, timestamp: now))
          .toList();

      _entries.addAll(duplicates);
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed.map((entry) => entry.toCsv()).join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError("${_selectedIndices.length} entries duplicated");
      _exitBulkEditMode();
    } catch (e) {
      _showError('Error duplicating entries: $e');
    }
  }

  Widget _buildEntry(WordEntry entry, int index) {
    final dt = DateTimeFormatter(entry.timestamp);
    final count = _wordFrequencies[entry.word] ?? 1;

    if (_bulkEditMode) {
      final actualIndex = _entries.indexOf(entry);
      final isSelected = _selectedIndices.contains(actualIndex);

      return ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                _selectedIndices.add(actualIndex);
              } else {
                _selectedIndices.remove(actualIndex);
              }
            });
          },
        ),
        title: Text(entry.word),
        subtitle: Text('${dt.weekDay} ${dt.date} ${dt.time}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dt.daysAgo, style: Theme.of(context).textTheme.bodySmall),
            if (count > 1) Text('x$count', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
        onTap: () {
          final actualIndex = _entries.indexOf(entry);
          setState(() {
            if (_selectedIndices.contains(actualIndex)) {
              _selectedIndices.remove(actualIndex);
            } else {
              _selectedIndices.add(actualIndex);
            }
          });
        },
      );
    }

    return Dismissible(
      key: Key('${entry.timestamp.millisecondsSinceEpoch}'),
      dismissThresholds: const {
        DismissDirection.endToStart: 0.9,
        DismissDirection.startToEnd: 0.9,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete Entry'),
              content: Text('Delete "${entry.word}"?'),
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
        } else {
          return true;
        }
      },
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(left: 20),
        child: Icon(Icons.add, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteEntry(entry);
        } else if (direction == DismissDirection.startToEnd) {
          _addEntry(entry.word);
        }
      },
      child: ListTile(
        title: Text(entry.word),
        subtitle: Text('${dt.weekDay} ${dt.date} ${dt.time}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dt.daysAgo, style: Theme.of(context).textTheme.bodySmall),
            if (count > 1) Text('x$count', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
        onTap: () => _editEntry(entry),
        onLongPress: () => _enterBulkEditMode(entry),
      ),
    );
  }

  Future<void> _loadEntries() async {
    try {
      final file = await getFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final lines = contents.split('\n').where((line) => line.isNotEmpty);
        final entries = lines.map((line) => WordEntry.fromCsv(line)).toList().reversed.toList();

        setState(() {
          _entries = entries;
          _displayEntries = List.from(entries);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showError("Error loading entries: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterEntries() {
    final text = _controller.text;

    if (text.isNotEmpty) {
      final trimmedText = text.trimRight();

      int lastTagIndex = -1;
      String? tagChar;

      for (int i = trimmedText.length - 1; i >= 0; i--) {
        if (tagLeaders.contains(trimmedText[i])) {
          if (i == 0 || trimmedText[i - 1] == ' ') {
            lastTagIndex = i;
            tagChar = trimmedText[i];
            break;
          }
        } else if (trimmedText[i] == ' ') {
          break;
        }
      }

      if (lastTagIndex != -1 && tagChar != null) {
        final partialTag = trimmedText.substring(lastTagIndex);
        final taggedWords = getTagSuggestions(tagChar, partialTag);

        // Filter entries by the full search text, not just the tag
        final matchingEntries = _entries.where((entry) {
          return entry.word.toLowerCase().contains(trimmedText.toLowerCase());
        }).toList();

        setState(() {
          _suggestions = taggedWords;
          _showSuggestions = taggedWords.isNotEmpty;
          _displayEntries = matchingEntries;
          _hasSearchText = true;
        });
        return;
      }
    }

    if (text.isEmpty) {
      setState(() {
        _displayEntries = List.from(_entries);
        _showSuggestions = false;
        _showAllMatches = false;
        _hasSearchText = false;
      });
      return;
    }

    final matchingEntries = _entries.where((entry) {
      return entry.word.toLowerCase().contains(text.toLowerCase());
    }).toList();

    if (_showAllMatches) {
      setState(() {
        _displayEntries = matchingEntries;
        _showSuggestions = false;
        _hasSearchText = true;
      });
      return;
    }

    final uniqueEntries = <String, WordEntry>{};
    for (final entry in matchingEntries) {
      final key = entry.word.split(':')[0].trim().toLowerCase();
      if (!uniqueEntries.containsKey(key) ||
          entry.timestamp.isAfter(uniqueEntries[key]!.timestamp)) {
        uniqueEntries[key] = entry;
      }
    }

    final uniqueList = uniqueEntries.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _displayEntries = uniqueList;
      _showSuggestions = false;
      _hasSearchText = true;
    });
  }

  List<String> getTagSuggestions(String tagChar, [String partialTag = '']) {
    final allTags = _entries
        .where((entry) => entry.word.contains(tagChar))
        .expand((entry) {
          final words = entry.word.split(' ');
          return words.where((word) => word.startsWith(tagChar));
        })
        .toSet()
        .toList();

    if (partialTag.isNotEmpty) {
      return allTags
          .where((tag) => tag.toLowerCase().startsWith(partialTag.toLowerCase()))
          .toList();
    }

    return allTags;
  }

  Map<String, int> _getTagFrequencies() {
    final tagCounts = <String, int>{};

    for (final entry in _entries) {
      final words = entry.word.split(' ');
      for (final word in words) {
        if (word.isNotEmpty && tagLeaders.contains(word[0])) {
          tagCounts[word] = (tagCounts[word] ?? 0) + 1;
        }
      }
    }

    return tagCounts;
  }

  List<MapEntry<String, int>> _getTagsSortedByFrequency() {
    final frequencies = _getTagFrequencies();
    final sortedEntries = frequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedEntries;
  }

  Future<void> _loadHotbarTags() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/bunyan_hotbar.txt');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final tags = contents.split('\n').where((line) => line.isNotEmpty).toList();
        setState(() {
          _hotbarTags = tags;
        });
      }
    } catch (e) {
      // Silently fail - hotbar is optional
    }
  }

  Future<void> _saveHotbarTags(List<String> tags) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/bunyan_hotbar.txt');
      await file.writeAsString(tags.join('\n'));

      setState(() {
        _hotbarTags = tags;
      });
    } catch (e) {
      _showError('Error saving hotbar settings: $e');
    }
  }

  Future<void> _resetEntries() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset All Data'),
          content: Text("Are you sure you want to delete all entries? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete All'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) return;
    try {
      final file = await getFile();
      if (await file.exists()) await file.delete();

      setState(() {
        _entries.clear();
        _displayEntries.clear();
      });
      _showError("Data reset successfully");
    } catch (e) {
      _showError('Error resetting data: $e');
    }
  }

  Future<void> _editEntry(WordEntry entryToEdit) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditEntryScreen(
          entry: entryToEdit,
          getTagSuggestions: getTagSuggestions,
          onSave: (editedEntry) async {
            await _updateEntry(entryToEdit, editedEntry);
          },
        ),
      ),
    );
  }

  Future<void> _updateEntry(WordEntry oldEntry, WordEntry newEntry) async {
    try {
      final actualIndex = _entries.indexWhere(
        (e) => e.timestamp == oldEntry.timestamp && e.word == oldEntry.word,
      );

      if (actualIndex == -1) return;

      setState(() {
        _entries[actualIndex] = newEntry;
        _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed.map((entry) => entry.toCsv()).join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError("Entry updated");
    } catch (e) {
      _showError('Error updating entry: $e');
    }
  }

  Future<void> _addEntry(String word) async {
    if (word.trim().isEmpty) return;

    final entry = WordEntry(word: word.trim(), timestamp: DateTime.now());

    try {
      final file = await getFile();
      await file.writeAsString('${entry.toCsv()}\n', mode: FileMode.append);

      setState(() {
        _entries.insert(0, entry);
        _displayEntries = List.from(_entries);
      });

      _controller.clear();
      _focusNode.requestFocus();
    } catch (e) {
      _showError("Error saving entry: $e");
    }
  }

  Future<void> _deleteEntry(WordEntry entryToDelete) async {
    try {
      final actualIndex = _entries.indexWhere(
        (e) => e.timestamp == entryToDelete.timestamp && e.word == entryToDelete.word,
      );

      if (actualIndex == -1) return;

      setState(() {
        _entries.removeAt(actualIndex);
        _displayEntries = _displayEntries
            .where((e) => e.timestamp != entryToDelete.timestamp || e.word != entryToDelete.word)
            .toList();
      });

      final file = await getFile();
      final csvContent = _entries.reversed.map((entry) => entry.toCsv()).join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }
    } catch (e) {
      _showError('Error deleting entry: $e');
    }
  }

  Future<void> _exportData() async {
    try {
      final file = await getFile();
      if (await file.exists()) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      } else {
        _showError("No data to export");
      }
    } catch (e) {
      _showError('Error exporting data: $e');
    }
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result == null || result.files.single.path == null) return;

      final selectedFile = File(result.files.single.path!);

      final contents = await selectedFile.readAsString();
      if (!contents.contains('","')) {
        _showError("Selected file doesn't appear to be a valid CSV");
        return;
      }

      final targetFile = await getFile();
      await selectedFile.copy(targetFile.path);
      await _loadEntries();

      _showError("Import successful!");
    } catch (e) {
      _showError('Error importing data: $e');
    }
  }

  Future<void> _openHotbarSettings() async {
    final tagsByFrequency = _getTagsSortedByFrequency();
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => HotbarSettingsScreen(
          currentHotbarTags: _hotbarTags,
          tagsByFrequency: tagsByFrequency,
        ),
      ),
    );

    if (result != null) {
      await _saveHotbarTags(result);
    }
  }

  Future<void> _openBackupScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BackupScreen(
          onRestore: () {
            _loadEntries(); // Reload entries after restore
          },
        ),
      ),
    );
  }

  void _openTimeSuggestions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TimeSuggestionsScreen(
          entries: _entries,
          onAddEntry: _addEntry,
        ),
      ),
    );
  }

  void _insertTag(String tag) {
    final currentText = _controller.text;
    final newText = currentText.isEmpty ? '$tag ' : '$currentText $tag ';
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newText.length);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final uniqueWords = _entries.map((e) => e.word.toLowerCase()).toSet().length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_bulkEditMode ? '${_selectedIndices.length} selected' : 'Bunyan'),
        leading: _bulkEditMode
            ? IconButton(icon: Icon(Icons.close), onPressed: _exitBulkEditMode)
            : null,
        actions: _bulkEditMode
            ? [
                if (_selectedIndices.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.copy),
                    onPressed: _bulkDuplicateEntries,
                    tooltip: 'Duplicate',
                  ),
                if (_selectedIndices.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: _bulkEditDateTime,
                    tooltip: 'Edit Date/Time',
                  ),
                if (_selectedIndices.length >= 2)
                  IconButton(
                    icon: Icon(Icons.merge),
                    onPressed: _combineEntries,
                    tooltip: 'Combine Entries',
                  ),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.access_time),
                  onPressed: _openTimeSuggestions,
                  tooltip: 'Time Suggestions',
                ),
                IconButton(
                  icon: Icon(Icons.settings),
                  onPressed: _openHotbarSettings,
                  tooltip: 'Hotbar Settings',
                ),
                IconButton(
                  icon: Icon(Icons.backup),
                  onPressed: _openBackupScreen,
                  tooltip: 'Backups',
                ),
                IconButton(
                  icon: Icon(Icons.delete_forever),
                  onPressed: _resetEntries,
                  tooltip: 'Reset Data',
                ),
                IconButton(
                  icon: Icon(Icons.import_export),
                  onPressed: _importData,
                  tooltip: 'Import Data',
                ),
                IconButton(
                  icon: Icon(Icons.share),
                  onPressed: _exportData,
                  tooltip: 'Export Data',
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_hotbarTags.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _hotbarTags.length,
                      itemBuilder: (context, index) {
                        final tag = _hotbarTags[index];
                        return Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            onPressed: () => _insertTag(tag),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(tag),
                          ),
                        );
                      },
                    ),
                  ),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    labelText: 'Enter a log',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () => _controller.clear(),
                    ),
                  ),
                  onSubmitted: _addEntry,
                  autofocus: true,
                ),
                if (_hasSearchText && !_showSuggestions)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      icon: Icon(_showAllMatches ? Icons.filter_1 : Icons.filter_list),
                      label: Text(_showAllMatches ? 'Show Unique' : 'Show All'),
                      onPressed: () {
                        setState(() {
                          _showAllMatches = !_showAllMatches;
                          _filterEntries();
                        });
                      },
                    ),
                  ),
                if (_showSuggestions)
                  Container(
                    margin: EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: _suggestions.map((suggestion) {
                        return ListTile(
                          dense: true,
                          title: Text(suggestion),
                          onTap: () {
                            final currentText = _controller.text;
                            int tagStartIndex = currentText.length;
                            for (int i = currentText.length - 1; i >= 0; i--) {
                              if (tagLeaders.contains(currentText[i])) {
                                if (i == 0 || currentText[i - 1] == ' ') {
                                  tagStartIndex = i;
                                  break;
                                }
                              }
                            }

                            final textBeforeTag = currentText.substring(0, tagStartIndex);
                            _controller.text = '$textBeforeTag$suggestion ';

                            _controller.selection = TextSelection.collapsed(
                              offset: _controller.text.length,
                            );

                            setState(() {
                              _showSuggestions = false;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total entries: ${_entries.length}', style: Theme.of(context).textTheme.bodyMedium),
                Text('Unique entries: $uniqueWords', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Divider(),
          Expanded(
            child: _displayEntries.isEmpty
                ? Center(
                    child: Text(
                      'No entries yet.\nStart by typing a word above!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: _displayEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _displayEntries[index];
                      return _buildEntry(entry, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
