import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';

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

/// The Stats tab: totals, what gets logged around this time of day, and
/// the most frequent entries.
class StatsScreen extends StatelessWidget {
  final List<WordEntry> entries;
  final int windowMinutes;
  final VoidCallback? onOpenMenu;
  final Future<void> Function(String word) onAddEntry;
  final void Function(String word) onOpenEntryStats;

  const StatsScreen({
    super.key,
    required this.entries,
    required this.windowMinutes,
    required this.onAddEntry,
    required this.onOpenEntryStats,
    this.onOpenMenu,
  });

  /// Entries logged at roughly this time of day, scored by frequency
  /// weighted by recency (30-day half-life).
  List<_ScoredSuggestion> _aroundNow() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final filtered = entries.where((entry) {
      if (isDoneText(entry.word)) return false;
      final entryMinutes = entry.timestamp.hour * 60 + entry.timestamp.minute;
      var diff = (entryMinutes - currentMinutes).abs();
      if (diff > 12 * 60) diff = 24 * 60 - diff;
      return diff <= windowMinutes;
    });

    final wordData = <String, _WordData>{};
    for (final entry in filtered) {
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

    final scored = <_ScoredSuggestion>[];
    for (final e in wordData.entries) {
      final daysAgo = now.difference(e.value.mostRecent).inHours / 24.0;
      final recencyWeight = 1.0 / (1.0 + daysAgo / 30.0);
      scored.add(
        _ScoredSuggestion(e.key, e.value.count, e.value.count * recencyWeight),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Most frequently logged entry texts, newest timestamp kept for context.
  List<_ScoredSuggestion> _topEntries() {
    final counts = <String, _WordData>{};
    for (final entry in entries) {
      if (isDoneText(entry.word)) continue;
      final key = entry.word.split(':')[0].trim();
      if (key.isEmpty) continue;
      final existing = counts[key];
      if (existing == null) {
        counts[key] = _WordData(1, entry.timestamp);
      } else {
        existing.count++;
        if (entry.timestamp.isAfter(existing.mostRecent)) {
          existing.mostRecent = entry.timestamp;
        }
      }
    }
    final scored = counts.entries
        .map((e) => _ScoredSuggestion(
              e.key,
              e.value.count,
              e.value.count.toDouble(),
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return scored;
  }

  String _formatTimeWindow() {
    final now = DateTime.now();
    String formatTime(DateTime dt) {
      final hour = dt.hour;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:${dt.minute.toString().padLeft(2, '0')} $period';
    }

    final start = now.subtract(Duration(minutes: windowMinutes));
    final end = now.add(Duration(minutes: windowMinutes));
    return '${formatTime(start)} - ${formatTime(end)}';
  }

  Widget _summary(BuildContext context) {
    final unique = entries.map((e) => e.word.toLowerCase()).toSet().length;
    final todos = entries.where((e) => isTodoText(e.word)).length;
    final habits = entries.where((e) => isHabitEntry(e.word)).length;

    Widget stat(String label, String value) {
      return Expanded(
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          stat('entries', '${entries.length}'),
          stat('unique', '$unique'),
          stat('todos', '$todos'),
          stat('habit logs', '$habits'),
        ],
      ),
    );
  }

  Widget _suggestionList(
    BuildContext context,
    List<_ScoredSuggestion> items,
    String subtitleSuffix,
    String emptyMessage, {
    required bool showStatsOnTap,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.word),
          subtitle: Text('${item.count}$subtitleSuffix'),
          onTap: showStatsOnTap ? () => onOpenEntryStats(item.word) : null,
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Log again',
            onPressed: () async {
              await onAddEntry(item.word);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added: ${item.word}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stats'),
          leading: onOpenMenu == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: onOpenMenu,
                ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Around now'),
              Tab(text: 'Most logged'),
            ],
          ),
        ),
        body: Column(
          children: [
            _summary(context),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Usually logged ${_formatTimeWindow()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _suggestionList(
                          context,
                          _aroundNow(),
                          'x around this time',
                          'No entries in this time window yet.',
                          showStatsOnTap: true,
                        ),
                      ),
                    ],
                  ),
                  _suggestionList(
                    context,
                    _topEntries(),
                    'x logged',
                    'No entries yet.',
                    showStatsOnTap: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
