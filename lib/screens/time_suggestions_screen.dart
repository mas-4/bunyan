import 'package:flutter/material.dart';

import '../models.dart';

class TimeSuggestionsScreen extends StatelessWidget {
  final List<WordEntry> entries;
  final Function(String) onAddEntry;

  const TimeSuggestionsScreen({
    super.key,
    required this.entries,
    required this.onAddEntry,
  });

  List<MapEntry<String, int>> _getTimeFilteredSuggestions() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Filter entries within 1 hour window (60 minutes before and after)
    final windowMinutes = 60;

    final filteredEntries = entries.where((entry) {
      final entryMinutes = entry.timestamp.hour * 60 + entry.timestamp.minute;

      // Handle wrap-around at midnight
      var diff = (entryMinutes - currentMinutes).abs();
      if (diff > 12 * 60) {
        diff = 24 * 60 - diff;
      }

      return diff <= windowMinutes;
    }).toList();

    // Count frequency of unique words
    final wordCounts = <String, int>{};
    for (final entry in filteredEntries) {
      wordCounts[entry.word] = (wordCounts[entry.word] ?? 0) + 1;
    }

    // Sort by frequency descending
    final sortedEntries = wordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries;
  }

  String _formatTimeWindow() {
    final now = DateTime.now();
    final startHour = (now.hour - 1 + 24) % 24;
    final endHour = (now.hour + 1) % 24;

    String formatHour(int hour) {
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour $period';
    }

    return '${formatHour(startHour)} - ${formatHour(endHour)}';
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _getTimeFilteredSuggestions();

    return Scaffold(
      appBar: AppBar(
        title: Text('Around Now'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Entries typically logged ${_formatTimeWindow()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ),
          Divider(),
          Expanded(
            child: suggestions.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                        'No entries found for this time window.\nLog more entries to see suggestions!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = suggestions[index];
                      return ListTile(
                        title: Text(suggestion.key),
                        subtitle: Text('${suggestion.value}x around this time'),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle_outline),
                          onPressed: () {
                            onAddEntry(suggestion.key);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added: ${suggestion.key}'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
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
