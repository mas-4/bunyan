import 'package:flutter/material.dart';

import '../models.dart';

class TagBrowserScreen extends StatefulWidget {
  final List<WordEntry> entries;
  final List<MapEntry<String, int>> tagsByFrequency;
  final Function(String) onAddEntry;

  const TagBrowserScreen({
    super.key,
    required this.entries,
    required this.tagsByFrequency,
    required this.onAddEntry,
  });

  @override
  State<TagBrowserScreen> createState() => _TagBrowserScreenState();
}

class _TagBrowserScreenState extends State<TagBrowserScreen> {
  String? _selectedTag;

  List<WordEntry> _entriesForTag(String tag) {
    return widget.entries.where((e) {
      return e.word.split(' ').any((w) =>
          w.toLowerCase() == tag.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTag != null) {
      final entries = _entriesForTag(_selectedTag!);
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedTag = null),
          ),
          title: Text(_selectedTag!),
        ),
        body: entries.isEmpty
            ? Center(child: Text('No entries found'))
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final dt = DateTimeFormatter(entry.timestamp);
                  return ListTile(
                    title: Text(entry.word),
                    subtitle: Text('${dt.date} ${dt.time}'),
                    trailing: IconButton(
                      icon: Icon(Icons.add_circle_outline),
                      onPressed: () {
                        widget.onAddEntry(entry.word);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added: ${entry.word}'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Tags')),
      body: widget.tagsByFrequency.isEmpty
          ? Center(child: Text('No tags found'))
          : ListView.builder(
              itemCount: widget.tagsByFrequency.length,
              itemBuilder: (context, index) {
                final tag = widget.tagsByFrequency[index];
                return ListTile(
                  title: Text(tag.key),
                  trailing: Text(
                    '${tag.value}x',
                    style: TextStyle(color: Colors.grey),
                  ),
                  onTap: () => setState(() => _selectedTag = tag.key),
                );
              },
            ),
    );
  }
}
