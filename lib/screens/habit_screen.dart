import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';
import '../habit_logic.dart';
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

const _sortModes = ['tag', 'alpha', 'due', 'strength'];
const _sortModeLabels = {
  'tag': 'By tag',
  'alpha': 'Alphabetical',
  'due': 'Next due',
  'strength': 'Strength',
};
const _sortModeIcons = {
  'tag': Icons.label_outline,
  'alpha': Icons.sort_by_alpha,
  'due': Icons.schedule,
  'strength': Icons.fitness_center,
};

/// Either a section header or a habit row, for building a flat list with headers.
class _HabitListItem {
  final String? header;
  final HabitInfo? habit;

  _HabitListItem.header(this.header) : habit = null;
  _HabitListItem.habit(this.habit) : header = null;

  bool get isHeader => header != null;
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
  static bool _filterLoaded = false;
  static String _sortMode = 'tag';
  static bool _sortLoaded = false;
  int _dayOffset = 0; // 0 = today is rightmost column; positive = shifted back
  double _dragAccumulator = 0;

  @override
  void initState() {
    super.initState();
    if (!_filterLoaded) {
      loadBoolSetting('habitFilterDueOnly').then((value) {
        if (mounted && value != _filterDueOnly) {
          setState(() => _filterDueOnly = value);
        } else {
          _filterDueOnly = value;
        }
        _filterLoaded = true;
      });
    }
    if (!_sortLoaded) {
      loadStringSetting('habitSortMode', defaultValue: 'tag').then((value) {
        if (_sortModes.contains(value)) {
          if (mounted && value != _sortMode) {
            setState(() => _sortMode = value);
          } else {
            _sortMode = value;
          }
        }
        _sortLoaded = true;
      });
    }
  }

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

    // Pre-build tag→timestamps index (one pass over all entries)
    final depHabits = habits.where((h) => h.spec is DependencyTagHabitSpec).toList();
    if (depHabits.isNotEmpty) {
      final neededTags = depHabits
          .map((h) => (h.spec as DependencyTagHabitSpec).tag.toLowerCase())
          .toSet();
      final tagTimestamps = <String, List<DateTime>>{};
      for (final tag in neededTags) {
        tagTimestamps[tag] = [];
      }

      for (final entry in widget.entries) {
        final words = entry.word.replaceAll(habitTagRegex, '').split(' ');
        for (final w in words) {
          final wLower = w.toLowerCase();
          for (final tag in neededTags) {
            if (wLower == tag || wLower.startsWith(tag)) {
              tagTimestamps[tag]!.add(entry.timestamp);
              break;
            }
          }
        }
      }

      for (final habit in depHabits) {
        final depSpec = habit.spec as DependencyTagHabitSpec;
        final timestamps = tagTimestamps[depSpec.tag.toLowerCase()]!;
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

    // Precompute sort keys to avoid recomputing in O(N log N) comparisons
    Map<String, int>? dueMap;
    Map<String, double>? strengthMap;

    if (_sortMode == 'due') {
      dueMap = {for (final h in habits) h.hash: nextDueDayIndex(h.spec, h.completions)};
    }
    if (_sortMode == 'strength') {
      strengthMap = {for (final h in habits) h.hash: calculateHabitStrength(h.spec, h.completions)};
    }

    // Sort based on current mode
    switch (_sortMode) {
      case 'tag':
        habits.sort((a, b) {
          final tagA = extractFirstTag(a.displayName)?.toLowerCase() ?? 'zzz';
          final tagB = extractFirstTag(b.displayName)?.toLowerCase() ?? 'zzz';
          final cmp = tagA.compareTo(tagB);
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
        break;
      case 'due':
        habits.sort((a, b) {
          final cmp = dueMap![a.hash]!.compareTo(dueMap[b.hash]!);
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
        break;
      case 'strength':
        habits.sort((a, b) {
          final cmp = strengthMap![a.hash]!.compareTo(strengthMap[b.hash]!);
          if (cmp != 0) return cmp;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
        break;
      default: // alpha
        habits.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    }

    return habits;
  }

  /// Build a flat list of items with section headers (tag mode only).
  List<_HabitListItem> _buildListItems(List<HabitInfo> habits) {
    if (_sortMode != 'tag') {
      return habits.map((h) => _HabitListItem.habit(h)).toList();
    }

    final items = <_HabitListItem>[];
    String? currentTag;

    for (final habit in habits) {
      final tag = extractFirstTag(habit.displayName) ?? 'Other';
      if (tag != currentTag) {
        currentTag = tag;
        items.add(_HabitListItem.header(tag));
      }
      items.add(_HabitListItem.habit(habit));
    }

    return items;
  }

  /// Build the 5-day header row.
  Widget _buildDayHeaders() {
    final today = DateTime.now();
    return Row(
      children: [
        const Expanded(flex: 3, child: SizedBox()),
        for (int i = 4; i >= 0; i--)
          Expanded(
            child: Center(
              child: Text(
                _dayLabel(today.subtract(Duration(days: i + _dayOffset))),
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
    if (diff <= 6) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[day.weekday - 1];
    }
    // Older dates: show M/D
    return '${day.month}/${day.day}';
  }

  Widget _buildSectionHeader(String tag) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        tag,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
      ),
    );
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
          // 5 day cells (oldest → newest, left to right)
          for (int i = 4; i >= 0; i--)
            Expanded(
              child: _buildDayCell(habit, today.subtract(Duration(days: i + _dayOffset))),
            ),
        ],
      ),
    );
  }

  bool _isMultiPerDay(HabitSpec spec) {
    if (spec is FrequencyHabitSpec && spec.periodUnit == 'd' && spec.count > 1) return true;
    if (spec is CompositeHabitSpec) return spec.specs.any(_isMultiPerDay);
    return false;
  }

  Widget _buildDayCell(HabitInfo habit, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final isFuture = dayStart.isAfter(todayStart);

    if (isFuture) return const SizedBox();

    final completed = habit.spec.completedOnDay(day, habit.completions);
    // Only consider completions up to this day so future completions
    // don't mask missed days (e.g. a 1d habit completed today shouldn't
    // make yesterday show "not due").
    final completionsUpToDay = habit.completions.where((c) =>
        DateTime(c.year, c.month, c.day).compareTo(dayStart) <= 0).toList();
    final isDue = habit.spec.isDueOnDay(day, completionsUpToDay);

    // Has completions — tap to add more, hold to remove
    if (completed > 0) {
      // Check if this is a multi-per-day habit (e.g. 2/d, 3/d)
      final isMultiPerDay = _isMultiPerDay(habit.spec);

      if (isMultiPerDay) {
        // Show count: amber if partial, green if fulfilled
        final fulfilled = !isDue;
        final bgColor = fulfilled ? Colors.green.shade100 : Colors.amber.shade100;
        final fgColor = fulfilled ? Colors.green.shade800 : Colors.amber.shade800;
        return Center(
          child: GestureDetector(
            onTap: () => _completeHabit(habit, day),
            onLongPress: () => _uncompleteHabit(habit, day),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '$completed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
            ),
          ),
        );
      }

      // Single-per-day: green checkmark
      return Center(
        child: GestureDetector(
          onTap: () => _completeHabit(habit, day),
          onLongPress: () => _uncompleteHabit(habit, day),
          child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
        ),
      );
    }

    if (isDue && dayStart.isBefore(todayStart)) {
      // Missed — past day that was due but not completed
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _completeHabit(habit, day),
          child: Icon(Icons.close, color: Colors.red.shade300, size: 22),
        ),
      );
    }

    if (isDue) {
      // Due today — open circle, tappable to complete
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _completeHabit(habit, day),
          child: Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 24),
        ),
      );
    }

    // Not due — green outline circle, tappable for early completion
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _completeHabit(habit, day),
        child: Icon(Icons.check_circle_outline, color: Colors.green.shade300, size: 24),
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

  void _showLegend() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Legend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _legendRow(Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 22), 'Due — tap to complete'),
            _legendRow(Icon(Icons.close, color: Colors.red.shade300, size: 22), 'Missed — tap to complete retroactively'),
            _legendRow(Icon(Icons.check_circle_outline, color: Colors.green.shade300, size: 22), 'Not due — tap to complete early'),
            _legendRow(Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: Text('1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
            ), 'Partially done — tap to add, hold to remove'),
            _legendRow(Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: Text('2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            ), 'Fully done — tap to add more, hold to remove'),
            const SizedBox(height: 8),
            Text('Swipe left/right on the days to scroll through time.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Widget icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 32, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  void _cycleSortMode() {
    final currentIndex = _sortModes.indexOf(_sortMode);
    final nextIndex = (currentIndex + 1) % _sortModes.length;
    setState(() => _sortMode = _sortModes[nextIndex]);
    saveStringSetting('habitSortMode', _sortMode);
  }

  @override
  Widget build(BuildContext context) {
    final habits = _buildHabitList();
    final listItems = _buildListItems(habits);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(
            icon: Icon(_sortModeIcons[_sortMode] ?? Icons.sort),
            tooltip: _sortModeLabels[_sortMode] ?? 'Sort',
            onPressed: _cycleSortMode,
          ),
          IconButton(
            icon: Icon(
              _filterDueOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            tooltip: _filterDueOnly ? 'Show all habits' : 'Show due only',
            onPressed: () {
              setState(() => _filterDueOnly = !_filterDueOnly);
              saveBoolSetting('habitFilterDueOnly', _filterDueOnly);
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Legend',
            onPressed: _showLegend,
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
          : GestureDetector(
              onHorizontalDragStart: (_) => _dragAccumulator = 0,
              onHorizontalDragUpdate: (details) {
                _dragAccumulator += details.delta.dx;
                const threshold = 40.0;
                if (_dragAccumulator > threshold) {
                  // Dragged right → go back in time
                  setState(() => _dayOffset += 1);
                  _dragAccumulator = 0;
                } else if (_dragAccumulator < -threshold) {
                  // Dragged left → go forward in time
                  setState(() => _dayOffset = (_dayOffset - 1).clamp(0, _dayOffset));
                  _dragAccumulator = 0;
                }
              },
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _buildDayHeaders(),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24),
                      itemCount: listItems.length,
                      itemBuilder: (context, index) {
                        final item = listItems[index];
                        if (item.isHeader) {
                          return _buildSectionHeader(item.header!);
                        }
                        return Column(
                          children: [
                            _buildHabitRow(item.habit!),
                            if (index < listItems.length - 1 && !listItems[index + 1].isHeader)
                              const Divider(height: 1),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
