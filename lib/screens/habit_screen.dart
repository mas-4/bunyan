import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';
import '../frequency_cache.dart';
import 'habit_detail_screen.dart';

/// Info about a single habit derived from scanning all entries.
class HabitInfo {
  final String hash;
  final String displayName;
  final HabitSpec spec;
  final String fullText; // most recent entry text (used when creating completions)
  final List<DateTime> completions;

  HabitInfo({
    required this.hash,
    required this.displayName,
    required this.spec,
    required this.fullText,
    required this.completions,
  });
}

class HabitScreen extends StatefulWidget {
  final List<WordEntry> entries;
  final EntryFrequencyCache cache;
  final Future<void> Function(String word) onAddEntry;
  final Future<void> Function(String word, DateTime timestamp) onAddEntryWithTimestamp;
  final Future<void> Function(WordEntry entry) onDeleteEntry;

  const HabitScreen({
    super.key,
    required this.entries,
    required this.cache,
    required this.onAddEntry,
    required this.onAddEntryWithTimestamp,
    required this.onDeleteEntry,
  });

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  static bool _filterDueOnly = false;

  List<HabitInfo> _buildHabitList() {
    // Group entries by content hash; most recent entry determines current spec
    final habitMap = <String, HabitInfo>{};
    // We need entries sorted oldest→newest so last write wins
    final sorted = List<WordEntry>.from(widget.entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final entry in sorted) {
      if (!isHabitEntry(entry.word)) continue;
      final hash = generateContentHash(entry.word);
      final spec = parseHabitSpec(entry.word);
      if (spec == null) continue;
      final content = extractHabitContent(entry.word);

      final existing = habitMap[hash];
      final completions = existing?.completions ?? <DateTime>[];
      completions.add(entry.timestamp);

      habitMap[hash] = HabitInfo(
        hash: hash,
        displayName: content,
        spec: spec,
        fullText: entry.word,
        completions: completions,
      );
    }

    var habits = habitMap.values.toList();

    // Resolve tag dependencies: scan all entries for matching tags
    for (final habit in habits) {
      if (habit.spec is DependencyTagHabitSpec) {
        final depSpec = habit.spec as DependencyTagHabitSpec;
        final tag = depSpec.tag.toLowerCase();
        final timestamps = <DateTime>[];
        for (final entry in widget.entries) {
          final words = entry.word.replaceAll(habitTagRegex, '').split(' ');
          for (final w in words) {
            if (w.toLowerCase() == tag || w.toLowerCase().startsWith(tag)) {
              timestamps.add(entry.timestamp);
              break;
            }
          }
        }
        timestamps.sort();
        depSpec.tagOccurrences = timestamps;
      }
    }

    // Remove discontinued habits
    habits = habits.where((h) => h.spec is! DiscontinuedHabitSpec).toList();

    if (_filterDueOnly) {
      final today = DateTime.now();
      habits = habits.where((h) => h.spec.isDueOnDay(today, h.completions)).toList();
    }

    // Sort alphabetically
    habits.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    return habits;
  }

  /// Build the 5-day header row (today → 4 days ago, right to left).
  Widget _buildDayHeaders() {
    final today = DateTime.now();
    return Row(
      children: [
        const Expanded(flex: 3, child: SizedBox()),
        for (int i = 4; i >= 0; i--)
          Expanded(
            child: Center(
              child: Text(
                _dayLabel(today.subtract(Duration(days: i))),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yest';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day.weekday - 1];
  }

  Widget _buildHabitRow(HabitInfo habit) {
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Name + spec badge
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HabitDetailScreen(
                    habit: habit,
                    entries: widget.entries,
                    onAddEntryWithTimestamp: widget.onAddEntryWithTimestamp,
                    onDeleteEntry: widget.onDeleteEntry,
                  ),
                ),
              ).then((_) { if (mounted) setState(() {}); }),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      habit.spec.displayLabel,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 5 day cells (4 days ago → today, left to right)
          for (int i = 4; i >= 0; i--)
            Expanded(
              child: _buildDayCell(habit, today.subtract(Duration(days: i))),
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(HabitInfo habit, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final isFuture = dayStart.isAfter(todayStart);

    if (isFuture) return const SizedBox();

    final completed = habit.spec.completedOnDay(day, habit.completions);
    final isDue = habit.spec.isDueOnDay(day, habit.completions);
    final isPast = dayStart.isBefore(todayStart);

    // Check coverage for multi-day interval habits
    bool isCovered = false;
    if (habit.spec is IntervalHabitSpec) {
      isCovered = (habit.spec as IntervalHabitSpec).isCoveredOnDay(day, habit.completions);
    }

    // Partially fulfilled: has completions but still due (e.g. 1/2 for @habit[2/d])
    // Show count in amber, tappable to add another or long-press to undo
    if (completed > 0 && isDue) {
      return Center(
        child: GestureDetector(
          onTap: () => _completeHabit(habit, day),
          onLongPress: () => _uncompleteHabit(habit, day),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$completed',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ),
      );
    }

    if (completed > 1) {
      // Multiple completions, fully satisfied: show count, tap to remove one
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _uncompleteHabit(habit, day),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$completed',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
          ),
        ),
      );
    }

    if (completed == 1) {
      // Single completion, fully satisfied: checkmark, tap to uncomplete
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _uncompleteHabit(habit, day),
          child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
        ),
      );
    }

    if (isCovered && !isDue) {
      // Covered by a multi-day habit
      return Center(
        child: Icon(Icons.check_circle_outline, color: Colors.green.shade300, size: 24),
      );
    }

    if (isPast && isDue) {
      // Missed — tappable to complete retroactively
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _completeHabit(habit, day),
          child: Icon(Icons.close, color: Colors.red.shade300, size: 22),
        ),
      );
    }

    if (isDue) {
      // Empty checkmark — clickable to complete
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _completeHabit(habit, day),
          child: Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 24),
        ),
      );
    }

    // Not due, not covered — tappable open circle for early completion
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _completeHabit(habit, day),
        child: Icon(Icons.radio_button_unchecked, color: Colors.grey.shade300, size: 24),
      ),
    );
  }

  Future<void> _completeHabit(HabitInfo habit, DateTime day) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dayStart = DateTime(day.year, day.month, day.day);

    if (dayStart.isBefore(todayStart)) {
      // Past day — show time picker
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: 12, minute: 0),
      );
      if (time == null || !mounted) return;
      final timestamp = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      await widget.onAddEntryWithTimestamp(habit.fullText, timestamp);
    } else {
      await widget.onAddEntry(habit.fullText);
    }
    if (mounted) setState(() {});
  }

  Future<void> _uncompleteHabit(HabitInfo habit, DateTime day) async {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Find the most recent matching entry on that day
    WordEntry? toDelete;
    for (final entry in widget.entries) {
      if (!isHabitEntry(entry.word)) continue;
      if (generateContentHash(entry.word) != habit.hash) continue;
      if (!entry.timestamp.isBefore(dayEnd) || entry.timestamp.isBefore(dayStart)) continue;
      if (toDelete == null || entry.timestamp.isAfter(toDelete.timestamp)) {
        toDelete = entry;
      }
    }

    if (toDelete != null) {
      final dateLabel = DateTimeFormatter(day).date;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove completion'),
          content: Text('Remove completion on $dateLabel?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.onDeleteEntry(toDelete);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final habits = _buildHabitList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(
            icon: Icon(
              _filterDueOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            tooltip: _filterDueOnly ? 'Show all habits' : 'Show due only',
            onPressed: () => setState(() => _filterDueOnly = !_filterDueOnly),
          ),
        ],
      ),
      body: habits.isEmpty
          ? Center(
              child: Text(
                _filterDueOnly
                    ? 'No habits due right now!'
                    : 'No habits yet.\nAdd entries with @habit[SPEC] to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _buildDayHeaders(),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24),
                    itemCount: habits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _buildHabitRow(habits[index]),
                  ),
                ),
              ],
            ),
    );
  }
}
