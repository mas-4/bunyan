import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

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
      // Follows system setting
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

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _controller.addListener(_onTextChanged);
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

  String _formatTime(DateTime dateTime) {
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

  String _formatDaysAgo(DateTime timestamp) {
    final daysAgo = DateTime.now().difference(timestamp).inDays;
    if (daysAgo == 0) {
      // Less than 24 hours - check if it's actually today or yesterday
      if (timestamp.day == DateTime.now().day) {
        return 'Today';
      } else {
        return 'Yesterday';
      }
    }
    return '${daysAgo}d ago';
  }
  Widget _buildEntryTile(WordEntry entry, int index) {
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
                    child: Text('Cancel')
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
        subtitle: Text(
          '${entry.timestamp.year}/${entry.timestamp.month.toString().padLeft(2, '0')}/${entry.timestamp.day.toString().padLeft(2, '0')} '
              '${_formatTime(entry.timestamp)}',
        ),
        trailing: Text(
          _formatDaysAgo(entry.timestamp),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => _editEntry(entry),
      ),
    );
  }
  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/bunyan.csv');
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
      final file = await _getFile();
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

  Future<void> _loadEntries() async {
    try {
      final file = await _getFile();
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

  Future<void> _addEntry(String word) async {
    if (word.trim().isEmpty) return;

    final entry = WordEntry(word: word.trim(), timestamp: DateTime.now());

    try {
      final file = await _getFile();
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

  void _onTextChanged() {
    final text = _controller.text.toLowerCase();

    if (text.isEmpty) {
      setState(() {
        _displayEntries = List.from(_entries);
      });
      return;
    }

    final matchingEntries = _entries
        .where((entry) => entry.word.toLowerCase().contains(text))
        .toList();

    setState(() {
      _displayEntries = matchingEntries;
    });
  }

  Future<void> _resetData() async {
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

    if (shouldReset == false) {
      return;
    }
    try {
      final file = await _getFile();
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
      final file = await _getFile();
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

      final targetFile = await _getFile();
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
        title: Text('Bunyan Life Logging'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_forever),
            onPressed: _resetData,
            tooltip: 'Reset Data',
          ),
          IconButton(
            icon: Icon(Icons.import_export),
            onPressed: _importData,
            tooltip: 'Reset Data',
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
                  'Unique words: $uniqueWords',
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
                      return _buildEntryTile(entry, index);
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
  final Function(WordEntry) onSave;

  const EditEntryScreen({super.key, required this.entry, required this.onSave});

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  late TextEditingController _wordController;
  late DateTime _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.entry.word);
    _selectedDateTime = widget.entry.timestamp;
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

    if (time != null) {
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
  }

  String _formatTime(DateTime dateTime) {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour = hour - 12;
    }
    String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final y = _selectedDateTime.year;
    final m = _selectedDateTime.month.toString().padLeft(2, '0');
    final d = _selectedDateTime.day.toString().padLeft(2, '0');
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
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Entry Text',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
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
                      subtitle: Text('$y/$m/$d'),
                      trailing: Icon(Icons.calendar_today),
                      onTap: _selectDate,
                    ),
                    ListTile(
                      title: Text('Time'),
                      subtitle: Text(_formatTime(_selectedDateTime)),
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
