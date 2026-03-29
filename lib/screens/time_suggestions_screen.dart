import 'package:flutter/material.dart';

import '../models.dart';

class TimeSuggestionsScreen extends StatelessWidget {
  final List<WordEntry> entries;
  final Function(String) onAddEntry;
  final int windowMinutes;

  const TimeSuggestionsScreen({
    super.key,
    required this.entries,
    required this.onAddEntry,
    required this.windowMinutes,
  });

  List<_ScoredSuggestion> _getTimeFilteredSuggestions() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final filteredEntries = entries.where((entry) {
      final entryMinutes = entry.timestamp.hour * 60 + entry.timestamp.minute;

      // Handle wrap-around at midnight
      var diff = (entryMinutes - currentMinutes).abs();
      if (diff > 12 * 60) {
        diff = 24 * 60 - diff;
      }

      return diff <= windowMinutes;
    }).toList();

    // Group entries by word, tracking count and most recent timestamp
    final wordData = <String, _WordData>{};
    for (final entry in filteredEntries) {
      final existing = wordData[entry.word];
      if (existing == null) {
        wordData[entry.word] = _WordData(1, entry.timestamp);
      } else {
        existing.count++;
        if (entry.timestamp.isAfter(existing.mostRecent)) {
          existing.mostRecent = entry.timestamp;
        }
      }
    }

    if (wordData.isEmpty) return [];

    // Compound score: frequency * recency_weight
    // Recency decays with a half-life of 30 days
    final scored = <_ScoredSuggestion>[];
    for (final e in wordData.entries) {
      final daysAgo = now.difference(e.value.mostRecent).inHours / 24.0;
      final recencyWeight = 1.0 / (1.0 + daysAgo / 30.0);
      final score = e.value.count * recencyWeight;
      scored.add(_ScoredSuggestion(e.key, e.value.count, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  String _formatTimeWindow() {
    final now = DateTime.now();
    final startTime = now.subtract(Duration(minutes: windowMinutes));
    final endTime = now.add(Duration(minutes: windowMinutes));

    String formatTime(DateTime dt) {
      final hour = dt.hour;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:${dt.minute.toString().padLeft(2, '0')} $period';
    }

    return '${formatTime(startTime)} - ${formatTime(endTime)}';
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
                        title: Text(suggestion.word),
                        subtitle: Text('${suggestion.count}x around this time'),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle_outline),
                          onPressed: () {
                            onAddEntry(suggestion.word);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added: ${suggestion.word}'),
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

class _WordData {
  int count;
  DateTime mostRecent;
  _WordData(this.count, this.mostRecent);
}

class _ScoredSuggestion {
  final String word;
  final int count;
  final double score;
  _ScoredSuggestion(this.word, this.count, this.score);
}
