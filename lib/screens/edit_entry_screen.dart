import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';

class EditEntryScreen extends StatefulWidget {
  final WordEntry entry;
  final List<WordEntry> allEntries;
  final int relatedEntriesWindow;
  final List<String> Function(String tagChar, String partialTag) getTagSuggestions;
  final Function(WordEntry) onSave;
  final Function(String word, DateTime timestamp) onAddRelated;

  const EditEntryScreen({
    super.key,
    required this.entry,
    required this.allEntries,
    required this.relatedEntriesWindow,
    required this.getTagSuggestions,
    required this.onSave,
    required this.onAddRelated,
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

  List<WordEntry> _getMatchingEntries() {
    final entryWord = widget.entry.word.trim();
    return widget.allEntries.where((e) => e.word.trim() == entryWord).toList();
  }

  List<int> _getWeekdayFrequency(List<WordEntry> entries) {
    final counts = List.filled(7, 0);
    for (final entry in entries) {
      // DateTime.weekday: 1 = Monday, 7 = Sunday
      counts[entry.timestamp.weekday - 1]++;
    }
    return counts;
  }

  List<int> _getTimePeriodFrequency(List<WordEntry> entries) {
    // Morning (5-11), Midday (11-14), Afternoon (14-17), Evening (17-21), Night (21-5)
    final counts = List.filled(5, 0);
    for (final entry in entries) {
      final hour = entry.timestamp.hour;
      if (hour >= 5 && hour < 11) {
        counts[0]++; // Morning
      } else if (hour >= 11 && hour < 14) {
        counts[1]++; // Midday
      } else if (hour >= 14 && hour < 17) {
        counts[2]++; // Afternoon
      } else if (hour >= 17 && hour < 21) {
        counts[3]++; // Evening
      } else {
        counts[4]++; // Night (21-5)
      }
    }
    return counts;
  }

  Widget _buildBarChart({
    required List<int> data,
    required List<String> labels,
    required Color barColor,
  }) {
    final maxY = data.reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 120,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY * 1.2 : 1,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${labels[group.x]}: ${rod.toY.toInt()}',
                  TextStyle(color: Colors.white, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) return SizedBox();
                  return Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      labels[index],
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  );
                },
                reservedSize: 24,
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: false),
          barGroups: List.generate(data.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data[index].toDouble(),
                  color: barColor,
                  width: labels.length > 5 ? 20 : 28,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  List<MapEntry<String, int>> _getRelatedEntries() {
    final entryWord = widget.entry.word.trim();
    final windowMinutes = widget.relatedEntriesWindow;

    // Find all entries matching the current word
    final matchingEntries = widget.allEntries
        .where((e) => e.word.trim() == entryWord)
        .toList();

    if (matchingEntries.isEmpty) return [];

    final relatedWords = <String, int>{};

    for (final matchingEntry in matchingEntries) {
      final matchTime = matchingEntry.timestamp;
      // Track entries counted for this specific matching entry to avoid
      // counting the same entry multiple times for the same match
      final countedForThisMatch = <int>{};

      for (final entry in widget.allEntries) {
        // Skip if same word
        if (entry.word.trim() == entryWord) continue;

        // Skip if already counted for this matching entry
        final entryId = entry.timestamp.millisecondsSinceEpoch;
        if (countedForThisMatch.contains(entryId)) continue;

        // Check if within time window (actual timestamp proximity)
        final timeDiff = entry.timestamp.difference(matchTime).inMinutes.abs();

        if (timeDiff <= windowMinutes) {
          countedForThisMatch.add(entryId);
          relatedWords[entry.word] = (relatedWords[entry.word] ?? 0) + 1;
        }
      }
    }

    // Sort by co-occurrence frequency
    final sorted = relatedWords.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted;
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
      body: Column(
        children: [
          Padding(
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
          Builder(
            builder: (context) {
              final matchingEntries = _getMatchingEntries();
              if (matchingEntries.length <= 5) return SizedBox();

              final weekdayData = _getWeekdayFrequency(matchingEntries);
              final timePeriodData = _getTimePeriodFrequency(matchingEntries);
              final weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final timePeriodLabels = ['Morn', 'Mid', 'Aftn', 'Eve', 'Night'];

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frequency (${matchingEntries.length} entries)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('By weekday', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              SizedBox(height: 4),
                              _buildBarChart(
                                data: weekdayData,
                                labels: weekdayLabels,
                                barColor: Colors.blue,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('By time of day', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              SizedBox(height: 4),
                              _buildBarChart(
                                data: timePeriodData,
                                labels: timePeriodLabels,
                                barColor: Colors.orange,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
          Divider(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Often logged nearby',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(width: 8),
                Text(
                  '(± ${widget.relatedEntriesWindow} min)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final relatedEntries = _getRelatedEntries();
                if (relatedEntries.isEmpty) {
                  return Center(
                    child: Text(
                      'No related entries found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: relatedEntries.length,
                  itemBuilder: (context, index) {
                    final related = relatedEntries[index];
                    return ListTile(
                      dense: true,
                      title: Text(related.key),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${related.value}x',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle_outline),
                            onPressed: () {
                              widget.onAddRelated(related.key, _selectedDateTime);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added: ${related.key}'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
