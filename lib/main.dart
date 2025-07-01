import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

const String tagLeaders = '!@#^&~+=\\|';

class DateTimeFormatter {
  final DateTime dateTime;

  DateTimeFormatter(this.dateTime);

  String get date {
    final y = dateTime.year;
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  String get weekDay {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dateTime.weekday - 1]; // weekday is 1-7, array is 0-6
  }

  String get time {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12; // Midnight = 12 AM
    } else if (hour > 12) {
      hour = hour - 12; // Convert to 12-hour
    }
    String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String get daysAgo {
    final tmp = DateTime.now();
    final today = DateTime(tmp.year, tmp.month, tmp.day);
    final calendarDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final daysAgo = today.difference(calendarDate).inDays;

    if (daysAgo == 0) {
      return 'Today';
    } else if (daysAgo == 1) {
      return 'Yesterday';
    }
    return '${daysAgo}d ago';
  }
}

Future<File> getFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan.csv');
}

void main() {
  runApp(WordLoggerApp());
}

class WordLoggerApp extends StatelessWidget {
  const WordLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bunyan Life Logging',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: ThemeMode.system,
      home: WordLoggerHome(),
    );
  }
}

class WordEntry {
  final String word;
  final DateTime timestamp;

  WordEntry({required this.word, required this.timestamp});

  String toCsv() {
    return '"${timestamp.toIso8601String()}","$word"';
  }

  static WordEntry fromCsv(String csvLine) {
    // Simple CSV parsing - handles quoted fields
    final parts = csvLine.split('","');
    final timestampStr = parts[0].replaceAll('"', '');
    final word = parts[1].replaceAll('"', '');
    return WordEntry(word: word, timestamp: DateTime.parse(timestampStr));
  }
}

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

  // Bulk edit variables
  bool _bulkEditMode = false;
  Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _controller.addListener(_filterEntries);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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

    // Date picker
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now,
    );

    if (date == null) return;

    // Time picker
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );

    if (time == null) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    try {
      // Update selected entries
      final indicesToUpdate = _selectedIndices.toList()..sort();

      for (int index in indicesToUpdate.reversed) {
        final entry = _entries[index];
        _entries[index] = WordEntry(word: entry.word, timestamp: newDateTime);
      }

      // Resort by timestamp (newest first)
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _displayEntries = List.from(_entries);
      });

      // Rewrite CSV file
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

  Widget _buildEntry(WordEntry entry, int index) {
    final dt = DateTimeFormatter(entry.timestamp);

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
        trailing: Text(
          dt.daysAgo,
          style: Theme.of(context).textTheme.bodySmall,
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
          // Confirm delete
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
          // Add again - no confirmation needed
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
        trailing: Text(
          dt.daysAgo,
          style: Theme.of(context).textTheme.bodySmall,
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
        final entries = lines
            .map((line) => WordEntry.fromCsv(line))
            .toList()
            .reversed
            .toList();

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

    // Check if last character is a tag symbol
    if (text.isNotEmpty && tagLeaders.contains(text[text.length - 1])) {
      final taggedWords = _showTagSuggestions(text[text.length - 1]);

      setState(() {
        _suggestions = taggedWords.take(5).toList();
        _showSuggestions = taggedWords.isNotEmpty;
        _displayEntries = List.from(_entries);
      });
      return;
    }

    // Regular filtering logic...
    if (text.isEmpty) {
      setState(() {
        _displayEntries = List.from(_entries);
        _showSuggestions = false;
      });
      return;
    }

    final matchingEntries = _entries
        .where((entry) => entry.word.toLowerCase().contains(text.toLowerCase()))
        .toList();

    setState(() {
      _displayEntries = matchingEntries;
      _showSuggestions = false;
    });
  }

  List<String> _showTagSuggestions(String tagChar) {
    // Extract just the tagged words (the part with the tag)
    return _entries
        .where((entry) => entry.word.contains(tagChar))
        .map((entry) {
          // Extract the tagged word from the entry
          final words = entry.word.split(' ');
          return words.firstWhere(
            (word) => word.startsWith(tagChar),
            orElse: () => '',
          );
        })
        .where((word) => word.isNotEmpty)
        .toSet() // Remove duplicates
        .toList();
  }

  Future<void> _resetEntries() async {
    final c = Text(
      "Are you sure you want to delete all entries? This cannot be undone.",
    );
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset All Data'),
          content: c,
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

    if (shouldReset == false) return;
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
          onSave: (editedEntry) async {
            await _updateEntry(entryToEdit, editedEntry);
          },
          parentState: this,
        ),
      ),
    );
  }

  Future<void> _updateEntry(WordEntry oldEntry, WordEntry newEntry) async {
    try {
      // Find the entry in the full list
      final actualIndex = _entries.indexWhere(
        (e) => e.timestamp == oldEntry.timestamp && e.word == oldEntry.word,
      );

      if (actualIndex == -1) return;

      setState(() {
        _entries[actualIndex] = newEntry;
        // Resort by timestamp (newest first)
        _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _displayEntries = List.from(_entries);
      });

      // Rewrite the entire CSV file
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

  Future<void> _addEntry(String word) async {
    if (word.trim().isEmpty) return;

    final entry = WordEntry(word: word.trim(), timestamp: DateTime.now());

    try {
      final file = await getFile();
      await file.writeAsString('${entry.toCsv()}\n', mode: FileMode.append);

      setState(() {
        _entries.insert(0, entry); // Add to beginning for recency
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
      // Find the entry in the full list
      final actualIndex = _entries.indexWhere(
        (e) =>
            e.timestamp == entryToDelete.timestamp &&
            e.word == entryToDelete.word,
      );

      if (actualIndex == -1) return;

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

      // Rest of your delete logic...
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

      // Check if it's actually a CSV by reading first line
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final uniqueWords = _entries
        .map((e) => e.word.toLowerCase())
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _bulkEditMode
              ? '${_selectedIndices.length} selected'
              : 'Bunyan Life Logging',
        ),
        leading: _bulkEditMode
            ? IconButton(icon: Icon(Icons.close), onPressed: _exitBulkEditMode)
            : null,
        actions: _bulkEditMode
            ? [
                if (_selectedIndices.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: _bulkEditDateTime,
                    tooltip: 'Edit Date/Time',
                  ),
              ]
            : [
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
          // Input section
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
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
                      icon: Icon(Icons.add),
                      onPressed: () => _addEntry(_controller.text),
                    ),
                  ),
                  onSubmitted: _addEntry,
                  autofocus: true,
                ),
                // In the TextField section, after the TextField:
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
                            // Remove the tag character that triggered the suggestions
                            final currentText = _controller.text;
                            final textWithoutTag = currentText.substring(
                              0,
                              currentText.length - 1,
                            );

                            // Append the selected tag
                            _controller.text = '$textWithoutTag$suggestion ';

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

          // Recent entries
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

class EditEntryScreen extends StatefulWidget {
  final WordEntry entry;
  final WordLoggerHomeState parentState; // Pass the parent state
  final Function(WordEntry) onSave;

  const EditEntryScreen({
    super.key,
    required this.entry,
    required this.parentState, // Add this
    required this.onSave,
  });

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  late TextEditingController _wordController;
  late DateTime _selectedDateTime;
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.entry.word);
    _selectedDateTime = widget.entry.timestamp;
    _wordController.addListener(_checkForTags);
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (date == null) return;
    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        _selectedDateTime.hour,
        _selectedDateTime.minute,
      );
    });
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );

    if (time == null) return;
    setState(() {
      _selectedDateTime = DateTime(
        _selectedDateTime.year,
        _selectedDateTime.month,
        _selectedDateTime.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _checkForTags() {
    final text = _wordController.text;

    if (text.isNotEmpty && tagLeaders.contains(text[text.length - 1])) {
      final suggestions = widget.parentState._showTagSuggestions(
        text[text.length - 1],
      );
      setState(() {
        _suggestions = suggestions.take(5).toList();
        _showSuggestions = suggestions.isNotEmpty;
      });
    } else {
      setState(() {
        _showSuggestions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dt = DateTimeFormatter(_selectedDateTime);
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Entry'),

        actions: [
          TextButton(
            onPressed: () {
              final editedEntry = WordEntry(
                word: _wordController.text.trim(),
                timestamp: _selectedDateTime,
              );
              widget.onSave(editedEntry);
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              maxLines: null,
              minLines: 1,
              textInputAction: TextInputAction.send,
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Entry Text',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            // Add this right after the TextField widget, before the SizedBox(height: 20)
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
                        // Remove the tag character that triggered the suggestions
                        final currentText = _wordController.text;
                        final textWithoutTag = currentText.substring(
                          0,
                          currentText.length - 1,
                        );

                        // Append the selected tag
                        _wordController.text = '$textWithoutTag$suggestion ';

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _wordController.selection = TextSelection.collapsed(
                            offset: _wordController.text.length,
                          );
                        });

                        setState(() {
                          _showSuggestions = false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),

            SizedBox(height: 20),
            Text('Date & Time', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 10),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Date'),
                      subtitle: Text(dt.date),
                      trailing: Icon(Icons.calendar_today),
                      onTap: _selectDate,
                    ),
                    ListTile(
                      title: Text('Time'),
                      subtitle: Text(dt.time),
                      trailing: Icon(Icons.access_time),
                      onTap: _selectTime,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
