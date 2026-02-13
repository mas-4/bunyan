import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:confetti/confetti.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import '../models.dart';
import '../utils.dart';
import '../frequency_cache.dart';
import 'edit_entry_screen.dart';
import 'entry_stats_screen.dart';
import 'hotbar_settings_screen.dart';
import 'backup_screen.dart';
import 'time_suggestions_screen.dart';
import 'settings_screen.dart';
import 'tag_manager_screen.dart';

class WordLoggerHome extends StatefulWidget {
  const WordLoggerHome({super.key});

  @override
  WordLoggerHomeState createState() => WordLoggerHomeState();
}

class WordLoggerHomeState extends State<WordLoggerHome> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late ConfettiController _confettiController;
  List<WordEntry> _entries = [];
  List<WordEntry> _displayEntries = [];
  bool _isLoading = true;
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  bool _showAllMatches = false;
  bool _hasSearchText = false;

  List<String> _hotbarTags = [];

  int _aroundNowWindow = defaultAroundNowWindow;
  int _relatedEntriesWindow = defaultRelatedEntriesWindow;

  bool _bulkEditMode = false;
  final Set<int> _selectedIndices = {};

  // Centralized frequency cache for O(1) lookups
  final EntryFrequencyCache _cache = EntryFrequencyCache();

  // Generate 8-char hash from text + timestamp for todo tracking
  String _generateTodoHash(String text, DateTime timestamp) {
    final combined = '$text${timestamp.toIso8601String()}';
    final bytes = utf8.encode(combined);
    int hash = 0;
    for (final byte in bytes) {
      hash = ((hash << 5) - hash) + byte;
      hash = hash & 0x7FFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }

  // Check if entry contains #todo
  bool _isTodoEntry(WordEntry entry) {
    return entry.word.toLowerCase().contains('#todo');
  }

  // Check if a todo entry has been completed
  bool _isTodoCompleted(WordEntry entry) {
    if (!_isTodoEntry(entry)) return false;
    final hash = _generateTodoHash(entry.word, entry.timestamp);
    return _cache.isDoneHash(hash);
  }

  // Check if currently filtering by #todo
  bool get _isFilteringTodo {
    final text = _controller.text.toLowerCase().trim();
    return text == '#todo' || text.contains('#todo');
  }

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: Duration(seconds: 1));
    _initializeApp();
    _controller.addListener(_filterEntries);
  }

  Future<void> _initializeApp() async {
    // Check for daily backup first
    await _checkDailyBackup();
    // Then load data
    await _loadEntries();
    await _loadHotbarTags();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await loadTimeSettings();
    setState(() {
      _aroundNowWindow = settings['aroundNow']!;
      _relatedEntriesWindow = settings['relatedEntries']!;
    });
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
    _confettiController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

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
      final selectedEntries =
          _selectedIndices.map((index) => _entries[index]).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final entryWords = selectedEntries
          .map((entry) => entry.word.replaceAll(':', ','))
          .join(', ');
      final combinedText = '$name: $entryWords';

      final latestTimestamp = selectedEntries
          .map((entry) => entry.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final combinedEntry = WordEntry(
        word: combinedText,
        timestamp: latestTimestamp,
      );

      final indicesToRemove = _selectedIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (int index in indicesToRemove) {
        _cache.removeEntry(_entries[index]);
        _entries.removeAt(index);
      }

      _entries.add(combinedEntry);
      _cache.addEntry(combinedEntry);
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

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
      final selectedEntries = _selectedIndices
          .map((index) => _entries[index])
          .toList();
      final now = DateTime.now();

      final duplicates = selectedEntries
          .map((entry) => WordEntry(word: entry.word, timestamp: now))
          .toList();

      _entries.addAll(duplicates);
      for (final entry in duplicates) {
        _cache.addEntry(entry);
      }
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

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
    final count = _cache.getWordCount(entry.word);

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
            if (count > 1)
              Text(
                'x$count',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
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
        leading: (_isFilteringTodo && _isTodoEntry(entry) && !_isTodoCompleted(entry))
            ? IconButton(
                icon: Icon(Icons.check_circle_outline),
                onPressed: () => _markTodoAsDone(entry),
                tooltip: 'Mark as done',
              )
            : null,
        title: Text(
          entry.word,
          style: (_isTodoEntry(entry) && _isTodoCompleted(entry) && !_isFilteringTodo)
              ? TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
              : null,
        ),
        subtitle: Text('${dt.weekDay} ${dt.date} ${dt.time}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dt.daysAgo, style: Theme.of(context).textTheme.bodySmall),
            if (count > 1)
              Text(
                'x$count',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
          ],
        ),
        onTap: () => (_hasSearchText && !_showAllMatches)
            ? _bulkEditText(entry.word)
            : _editEntry(entry),
        onLongPress: () => (_hasSearchText && !_showAllMatches)
            ? _openEntryStats(entry.word)
            : _enterBulkEditMode(entry),
      ),
    );
  }

  Future<void> _loadEntries() async {
    try {
      final file = await getFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final lines = contents.split('\n').where((line) => line.isNotEmpty);
        final entries = lines
            .map((line) => WordEntry.fromCsv(line))
            .toList()
            .reversed
            .toList();

        _cache.buildFromEntries(entries);

        setState(() {
          _entries = entries;
          _displayEntries = List.from(entries);
          _isLoading = false;
        });
      } else {
        _cache.buildFromEntries([]);
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
        // Also hide completed todos when filtering by #todo
        final isFilteringForTodo = trimmedText.toLowerCase().contains('#todo');
        final matchingEntries = _entries.where((entry) {
          final matches = entry.word.toLowerCase().contains(trimmedText.toLowerCase());
          if (isFilteringForTodo && _isTodoEntry(entry) && _isTodoCompleted(entry)) {
            return false;
          }
          return matches;
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

    // Hide completed todos when filtering by #todo
    final isFilteringForTodo = text.toLowerCase().contains('#todo');
    final matchingEntries = _entries.where((entry) {
      final matches = entry.word.toLowerCase().contains(text.toLowerCase());
      if (isFilteringForTodo && _isTodoEntry(entry) && _isTodoCompleted(entry)) {
        return false;
      }
      return matches;
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
    return _cache.getTagSuggestions(tagChar, partialTag);
  }

  List<MapEntry<String, int>> _getTagsSortedByFrequency() {
    return _cache.getTagsSortedByFrequency();
  }

  Future<void> _loadHotbarTags() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/bunyan_hotbar.txt');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final tags = contents
            .split('\n')
            .where((line) => line.isNotEmpty)
            .toList();
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
          content: Text(
            "Are you sure you want to delete all entries? This cannot be undone.",
          ),
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

      _cache.buildFromEntries([]);
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
          allEntries: _entries,
          relatedEntriesWindow: _relatedEntriesWindow,
          getTagSuggestions: getTagSuggestions,
          onSave: (editedEntry) async {
            await _updateEntry(entryToEdit, editedEntry);
          },
          onAddRelated: (word, timestamp) async {
            await _addEntryWithTimestamp(word, timestamp);
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

      _cache.removeEntry(oldEntry);
      _cache.addEntry(newEntry);

      setState(() {
        _entries[actualIndex] = newEntry;
        _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

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

  Future<void> _bulkEditText(String oldWord) async {
    final oldWordTrimmed = oldWord.trim();
    final controller = TextEditingController(text: oldWordTrimmed);
    final matchingCount = _entries
        .where((e) => e.word.trim() == oldWordTrimmed)
        .length;

    final newWord = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit All Matching Entries'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$matchingCount entries will be updated'),
            SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'New text',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (value) => Navigator.pop(context, value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Update All'),
          ),
        ],
      ),
    );

    if (newWord == null || newWord.isEmpty || newWord == oldWordTrimmed) return;

    try {
      int updatedCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        if (_entries[i].word.trim() == oldWordTrimmed) {
          final oldEntry = _entries[i];
          final newEntry = WordEntry(
            word: newWord,
            timestamp: _entries[i].timestamp,
          );
          _cache.removeEntry(oldEntry);
          _cache.addEntry(newEntry);
          _entries[i] = newEntry;
          updatedCount++;
        }
      }

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError('$updatedCount entries updated');
      _controller.clear();
    } catch (e) {
      _showError('Error updating entries: $e');
    }
  }

  Future<void> _addEntry(String word, {bool clearController = true}) async {
    if (word.trim().isEmpty) return;

    final entry = WordEntry(word: word.trim(), timestamp: DateTime.now());

    try {
      final file = await getFile();
      await file.writeAsString('${entry.toCsv()}\n', mode: FileMode.append);

      _cache.addEntry(entry);

      setState(() {
        _entries.insert(0, entry);
        _filterEntries();
      });

      if (clearController) {
        _controller.clear();
        _focusNode.requestFocus();
      }
    } catch (e) {
      _showError("Error saving entry: $e");
    }
  }

  Future<void> _addEntryWithTimestamp(String word, DateTime timestamp) async {
    if (word.trim().isEmpty) return;

    final entry = WordEntry(word: word.trim(), timestamp: timestamp);

    try {
      final file = await getFile();
      await file.writeAsString('${entry.toCsv()}\n', mode: FileMode.append);

      _cache.addEntry(entry);

      setState(() {
        _entries.add(entry);
        _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _displayEntries = List.from(_entries);
      });
    } catch (e) {
      _showError("Error saving entry: $e");
    }
  }

  Future<void> _markTodoAsDone(WordEntry todoEntry) async {
    if (!_isTodoEntry(todoEntry)) return;

    final hash = _generateTodoHash(todoEntry.word, todoEntry.timestamp);
    // Remove #todo from the text to avoid infinite loops
    final cleanedText = todoEntry.word.replaceAll(RegExp(r'#todo', caseSensitive: false), '').trim();
    final doneText = '#done $hash $cleanedText';

    await _addEntry(doneText, clearController: false);
    _confettiController.play();
  }

  Future<void> _deleteEntry(WordEntry entryToDelete) async {
    try {
      final actualIndex = _entries.indexWhere(
        (e) =>
            e.timestamp == entryToDelete.timestamp &&
            e.word == entryToDelete.word,
      );

      if (actualIndex == -1) return;

      _cache.removeEntry(entryToDelete);

      setState(() {
        _entries.removeAt(actualIndex);
        _displayEntries = _displayEntries
            .where(
              (e) =>
                  e.timestamp != entryToDelete.timestamp ||
                  e.word != entryToDelete.word,
            )
            .toList();
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

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
          windowMinutes: _aroundNowWindow,
        ),
      ),
    );
  }

  Future<void> _openTagManager() async {
    final tagsByFrequency = _getTagsSortedByFrequency();
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => TagManagerScreen(
          tagsByFrequency: tagsByFrequency,
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      int updatedCount = 0;
      for (int i = 0; i < _entries.length; i++) {
        final words = _entries[i].word.split(' ');
        bool changed = false;
        for (int j = 0; j < words.length; j++) {
          if (result.containsKey(words[j])) {
            words[j] = result[words[j]]!;
            changed = true;
          }
        }
        if (changed) {
          final oldEntry = _entries[i];
          final newEntry = WordEntry(
            word: words.join(' '),
            timestamp: oldEntry.timestamp,
          );
          _cache.removeEntry(oldEntry);
          _cache.addEntry(newEntry);
          _entries[i] = newEntry;
          updatedCount++;
        }
      }

      setState(() {
        _displayEntries = List.from(_entries);
      });

      final file = await getFile();
      final csvContent = _entries.reversed
          .map((entry) => entry.toCsv())
          .join('\n');

      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString('');
      }

      _showError('$updatedCount entries updated');
    } catch (e) {
      _showError('Error renaming tags: $e');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          aroundNowWindow: _aroundNowWindow,
          relatedEntriesWindow: _relatedEntriesWindow,
          onSave: (aroundNow, relatedEntries) async {
            await saveTimeSettings(aroundNow, relatedEntries);
            setState(() {
              _aroundNowWindow = aroundNow;
              _relatedEntriesWindow = relatedEntries;
            });
          },
        ),
      ),
    );
  }

  void _openEntryStats(String entryWord) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntryStatsScreen(
          entryWord: entryWord.trim(),
          allEntries: _entries,
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
    final uniqueWords = _entries
        .map((e) => e.word.toLowerCase())
        .toSet()
        .length;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
        title: Text(
          _bulkEditMode ? '${_selectedIndices.length} selected' : 'Bunyan 🪓',
        ),
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
              ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Text(
                'Bunyan 🪓',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.backup),
              title: Text('Backups'),
              onTap: () {
                Navigator.pop(context);
                _openBackupScreen();
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Hotbar Settings'),
              onTap: () {
                Navigator.pop(context);
                _openHotbarSettings();
              },
            ),
            ListTile(
              leading: Icon(Icons.label),
              title: Text('Manage Tags'),
              onTap: () {
                Navigator.pop(context);
                _openTagManager();
              },
            ),
            ListTile(
              leading: Icon(Icons.tune),
              title: Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.file_download),
              title: Text('Import Data'),
              onTap: () {
                Navigator.pop(context);
                _importData();
              },
            ),
            ListTile(
              leading: Icon(Icons.share),
              title: Text('Export Data'),
              onTap: () {
                Navigator.pop(context);
                _exportData();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red),
              title: Text('Reset Data', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _resetEntries();
              },
            ),
          ],
        ),
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
                      icon: Icon(
                        _showAllMatches ? Icons.filter_1 : Icons.filter_list,
                      ),
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

                            final textBeforeTag = currentText.substring(
                              0,
                              tagStartIndex,
                            );
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
                Text(
                  'Total entries: ${_entries.length}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Unique entries: $uniqueWords',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
    ),
    Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: _confettiController,
        blastDirection: pi / 2,
        blastDirectionality: BlastDirectionality.explosive,
        maxBlastForce: 20,
        minBlastForce: 8,
        emissionFrequency: 0.05,
        numberOfParticles: 25,
        gravity: 0.2,
        colors: const [
          Colors.green,
          Colors.blue,
          Colors.pink,
          Colors.orange,
          Colors.purple,
          Colors.yellow,
        ],
      ),
    ),
  ],
);
  }
}
