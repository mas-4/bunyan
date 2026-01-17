import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';

class EditEntryScreen extends StatefulWidget {
  final WordEntry entry;
  final List<String> Function(String tagChar, String partialTag) getTagSuggestions;
  final Function(WordEntry) onSave;

  const EditEntryScreen({
    super.key,
    required this.entry,
    required this.getTagSuggestions,
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
        final suggestions = widget.getTagSuggestions(tagChar, partialTag);
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = suggestions.isNotEmpty;
        });
        return;
      }
    }

    setState(() {
      _showSuggestions = false;
    });
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
                        final currentText = _wordController.text;
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
                        _wordController.text = '$textBeforeTag$suggestion ';

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
