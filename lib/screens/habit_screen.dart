import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final VoidCallback? onOpenMenu;

  const HabitScreen({
    super.key,
    required this.entries,
    required this.cache,
    this.onOpenMenu,
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

  late ConfettiController _confettiController;
  late ConfettiController _fireworksController;

  /// Keys of cells that just got completed, for pop animation.
  /// Format: "hash:yyyy-mm-dd"
  final Set<String> _animatingCells = {};

  String _cellKey(String hash, DateTime day) =>
      '$hash:${day.year}-${day.month}-${day.day}';

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(milliseconds: 800));
    _fireworksController = ConfettiController(duration: const Duration(seconds: 2));
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

    // Pre-build hash→timestamps index for hash-based dependency habits
    final hashDepHabits = habits.where((h) => h.spec is DependencyHabitSpec).toList();
    if (hashDepHabits.isNotEmpty) {
      final neededHashes = <String>{};
      for (final h in hashDepHabits) {
        neededHashes.add((h.spec as DependencyHabitSpec).dependencyHash.toLowerCase());
      }

      final hashTimestamps = <String, List<DateTime>>{};
      for (final hash in neededHashes) {
        hashTimestamps[hash] = [];
      }

      for (final entry in widget.entries) {
        final entryHash = generateContentHash(entry.word).toLowerCase();
        if (hashTimestamps.containsKey(entryHash)) {
          hashTimestamps[entryHash]!.add(entry.timestamp);
        }
      }

      for (final habit in hashDepHabits) {
        final depSpec = habit.spec as DependencyHabitSpec;
        final timestamps = hashTimestamps[depSpec.dependencyHash.toLowerCase()]!;
        timestamps.sort();
        depSpec.hashOccurrences = timestamps;
      }
    }

    // Pre-build tag→timestamps index (one pass over all entries)
    final depHabits = habits.where((h) => h.spec is DependencyTagHabitSpec).toList();
    final negTagHabits = habits.where((h) => h.spec is NegativeTagHabitSpec).toList();
    final allTagHabits = [...depHabits, ...negTagHabits];
    if (allTagHabits.isNotEmpty) {
      final neededTags = <String>{};
      for (final h in depHabits) {
        neededTags.add((h.spec as DependencyTagHabitSpec).tag.toLowerCase());
      }
      for (final h in negTagHabits) {
        neededTags.add((h.spec as NegativeTagHabitSpec).tag.toLowerCase());
      }
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
      for (final habit in negTagHabits) {
        final negSpec = habit.spec as NegativeTagHabitSpec;
        final timestamps = tagTimestamps[negSpec.tag.toLowerCase()]!;
        timestamps.sort();
        negSpec.tagOccurrences = timestamps;
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
    final streak = calculateCurrentStreak(habit.spec, habit.completions, today: today);

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
              child: _wrapWithAnimation(
                habit.hash,
                today.subtract(Duration(days: i + _dayOffset)),
                _buildDayCell(habit, today.subtract(Duration(days: i + _dayOffset)), streak: streak),
              ),
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

  Widget _wrapWithAnimation(String hash, DateTime day, Widget child) {
    final cellKey = _cellKey(hash, day);
    if (!_animatingCells.contains(cellKey)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('anim_$cellKey'),
      tween: Tween(begin: 1.4, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }

  bool _isNegativeSpec(HabitSpec spec) =>
      spec is NegativeHabitSpec || spec is NegativeTagHabitSpec;

  Widget _buildDayCell(HabitInfo habit, DateTime day, {int streak = 0}) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final isFuture = dayStart.isAfter(todayStart);

    if (isFuture) return const SizedBox();

    final completed = habit.spec.completedOnDay(day, habit.completions);

    // Negative habits: inverted display
    if (_isNegativeSpec(habit.spec)) {
      return _buildNegativeDayCell(habit, day, completed);
    }

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

      // Single-per-day: flame if streak >= 5, otherwise green checkmark
      return Center(
        child: GestureDetector(
          onTap: () => _completeHabit(habit, day),
          onLongPress: () => _uncompleteHabit(habit, day),
          child: streak >= 5
              ? Icon(Icons.local_fire_department, color: Colors.orange, size: 24)
              : Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
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

  Widget _buildNegativeDayCell(HabitInfo habit, DateTime day, int completed) {
    if (completed == 0) {
      // No occurrences — green check (avoided, good)
      return Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _completeHabit(habit, day),
          child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
        ),
      );
    }

    if (completed == 1) {
      // Slipped once — red X
      return Center(
        child: GestureDetector(
          onTap: () => _uncompleteHabit(habit, day),
          onLongPress: () => _completeHabit(habit, day),
          child: Icon(Icons.cancel, color: Colors.red.shade400, size: 24),
        ),
      );
    }

    // Multiple slips — red number badge
    return Center(
      child: GestureDetector(
        onTap: () => _uncompleteHabit(habit, day),
        onLongPress: () => _completeHabit(habit, day),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '$completed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
        ),
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
    if (mounted) {
      HapticFeedback.mediumImpact();
      final key = _cellKey(habit.hash, day);
      _animatingCells.add(key);
      _confettiController.play();

      // Check if this completion brings the streak to exactly 5
      final newStreak = calculateCurrentStreak(habit.spec, habit.completions);
      if (newStreak == 5) {
        _fireworksController.play();
      }

      setState(() {});
      // Remove animation key after animation completes
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _animatingCells.remove(key));
      });
    }
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
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
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
              const Divider(height: 32),
              Text('Habit Syntax', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _helpText('Add @habit[SPEC] to any entry to track it as a habit. '
                  'Completions are just duplicate entries with the same text.'),
              _helpSub('Interval (every N days/weeks/months)'),
              _helpCode('@habit[1d]  @habit[2d]  @habit[7d]\n'
                  '@habit[1w]  @habit[2w]\n'
                  '@habit[1m]  @habit[3m]  @habit[1y]'),
              _helpSub('Frequency (N times per period)'),
              _helpCode('@habit[2/d]  2x per day\n'
                  '@habit[3/w]  3x per week\n'
                  '@habit[2/m]  2x per month'),
              _helpSub('Sliding window'),
              _helpCode('@habit[3 in 7d]  3 times in any 7-day window\n'
                  '@habit[5 in 2w]  5 times in any 2-week window'),
              _helpSub('Calendar-anchored'),
              _helpCode('@habit[every monday]\n'
                  '@habit[every march]\n'
                  '@habit[13th]           13th of every month\n'
                  '@habit[march 13th]     specific date yearly'),
              _helpSub('Dependency (hash or tag)'),
              _helpCode('@habit[after 7 a3f7]  activates after 7\n'
                  '                      entries matching hash a3f7\n'
                  '@habit[every 3 @run]  activates every 3 entries\n'
                  '                      containing tag @run'),
              _helpText('Tag dependencies match any entry containing the tag, '
                  'e.g. both "@run long" and "@run base" count toward '
                  '@habit[every 3 @run]. The count resets after each completion.'),
              _helpSub('Negative (avoid tracking)'),
              _helpCode('@habit[not 1d]         avoid daily\n'
                  '@habit[not 3 @smoke]   track avoidance by tag'),
              _helpSub('Rescheduling & ending'),
              _helpText('To change a schedule, add a new entry with the updated spec. '
                  'The most recent entry per hash determines the current schedule.'),
              _helpCode('@habit  (no brackets) = habit ended/paused'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
    );
  }

  Widget _helpSub(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _helpCode(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey.shade800, height: 1.5),
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
  void dispose() {
    _confettiController.dispose();
    _fireworksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final habits = _buildHabitList();
    final listItems = _buildListItems(habits);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenMenu,
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Legend',
            onPressed: _showLegend,
          ),
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
        ],
      ),
      body: Stack(
        children: [
          habits.isEmpty
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
          // Confetti on every completion
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2,
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 15,
              minBlastForce: 5,
              emissionFrequency: 0.06,
              numberOfParticles: 10,
              gravity: 0.3,
            ),
          ),
          // Fireworks on 5-day streak
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _fireworksController,
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 30,
              minBlastForce: 10,
              emissionFrequency: 0.08,
              numberOfParticles: 30,
              gravity: 0.1,
              colors: const [
                Colors.orange,
                Colors.red,
                Colors.yellow,
                Colors.amber,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
