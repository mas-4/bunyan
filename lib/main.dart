import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  List<String> _suggestions = [];
  bool _showSuggestions = false;
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

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/bunyan.csv');
  }

  Future<void> _loadEntries() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final lines = contents.split('\n').where((line) => line.isNotEmpty);

        setState(() {
          _entries = lines.map((line) => WordEntry.fromCsv(line)).toList();
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
        _showSuggestions = false;
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
        _showSuggestions = false;
      });
      return;
    }

    // Get unique words that start with the input, sorted by most recent
    final matchingEntries = _entries
        .where((entry) => entry.word.toLowerCase().startsWith(text))
        .toList();

    // Remove duplicates while preserving order (most recent first)
    final uniqueWords = <String>[];
    final seen = <String>{};

    for (final entry in matchingEntries) {
      if (!seen.contains(entry.word.toLowerCase())) {
        seen.add(entry.word.toLowerCase());
        uniqueWords.add(entry.word);
      }
    }

    setState(() {
      _suggestions = uniqueWords.take(5).toList(); // Limit to 5 suggestions
      _showSuggestions = uniqueWords.isNotEmpty;
    });
  }

  Future<void> _resetData() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset All Data'),
          content: Text(
            'Are you sure you want to delete all entries? This cannot be undone.',
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

    if (shouldReset == true) {
      try {
        final file = await _getFile();
        if (await file.exists()) {
          await file.delete();
        }
        setState(() {
          _entries.clear();
        });
        _showError("Data reset successfully");
      } catch (e) {
        _showError('Error resetting data: $e');
      }
    }
  }

  Future<void> _deleteEntry(int index) async {
    try {
      // Remove from memory
      setState(() {
        _entries.removeAt(index);
      });

      // Rewrite the entire CSV file
      final file = await _getFile();
      final csvContent = _entries.map((entry) => entry.toCsv()).join('\n');
      if (csvContent.isNotEmpty) {
        await file.writeAsString('$csvContent\n');
      } else {
        await file.writeAsString(''); // Empty file if no entries
      }

      _showError("Entry deleted");
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                    labelText: 'Enter a word',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.add),
                      onPressed: () => _addEntry(_controller.text),
                    ),
                  ),
                  onSubmitted: _addEntry,
                  autofocus: true,
                ),
                // Suggestions
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
                            _controller.text = suggestion;
                            _addEntry(suggestion);
                          },
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),

          // Stats
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
                  'Unique words: ${_entries.map((e) => e.word.toLowerCase()).toSet().length}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          Divider(),

          // Recent entries
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      'No entries yet.\nStart by typing a word above!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return Dismissible(
                        key: Key('${entry.timestamp.millisecondsSinceEpoch}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.only(right: 20),
                          child: Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) => _deleteEntry(index),
                        child: ListTile(
                          title: Text(entry.word),
                          subtitle: Text(
                            '${entry.timestamp.day}/${entry.timestamp.month}/${entry.timestamp.year} '
                            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                            '${entry.timestamp.minute.toString().padLeft(2, '0')}',
                          ),
                          trailing: Text(
                            '${DateTime.now().difference(entry.timestamp).inDays}d ago',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
