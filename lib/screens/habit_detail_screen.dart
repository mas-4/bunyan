import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';
import 'habit_screen.dart';

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

class HabitDetailScreen extends StatefulWidget {
  final HabitInfo habit;
  final List<WordEntry> entries;
  final Future<void> Function(String word, DateTime timestamp) onAddEntryWithTimestamp;
  final Future<void> Function(WordEntry entry) onDeleteEntry;

  const HabitDetailScreen({
    super.key,
    required this.habit,
    required this.entries,
    required this.onAddEntryWithTimestamp,
    required this.onDeleteEntry,
  });

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  late DateTime _calendarMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month, 1);
  }

  // ------------------------------------------------------------------
  // Summary
  // ------------------------------------------------------------------

  Widget _buildSummaryCard(BuildContext context) {
    final completions = widget.habit.completions;
    final sorted = List<DateTime>.from(completions)..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem(context, 'Total', '${completions.length}'),
            if (sorted.isNotEmpty)
              _statItem(context, 'First', DateTimeFormatter(sorted.first).date),
            if (sorted.isNotEmpty)
              _statItem(context, 'Last', DateTimeFormatter(sorted.last).date),
          ],
        ),
      ),
    );
  }

  Widget _statItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Next Due
  // ------------------------------------------------------------------

  Widget _buildNextDue() {
    final spec = widget.habit.spec;

    // Special-case DependencyTagHabitSpec
    if (spec is DependencyTagHabitSpec) {
      return _buildDepTagNextDue(spec);
    }

    final today = _startOfDay(DateTime.now());
    DateTime? nextDue;

    for (int i = 0; i <= 366; i++) {
      final day = today.add(Duration(days: i));
      if (spec.isDueOnDay(day, widget.habit.completions)) {
        nextDue = day;
        break;
      }
    }

    if (nextDue == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.event_available, color: Colors.green),
          title: const Text('Next Due'),
          subtitle: const Text('Not due within the next year'),
        ),
      );
    }

    final daysAway = nextDue.difference(today).inDays;
    Color color;
    String label;
    if (daysAway < 0) {
      color = Colors.red;
      label = '${-daysAway} day${-daysAway == 1 ? '' : 's'} overdue';
    } else if (daysAway == 0) {
      color = Colors.amber.shade700;
      label = 'Due today';
    } else {
      color = Colors.green;
      label = 'In $daysAway day${daysAway == 1 ? '' : 's'}';
    }

    return Card(
      child: ListTile(
        leading: Icon(Icons.event, color: color),
        title: const Text('Next Due'),
        subtitle: Text(
          '${DateTimeFormatter(nextDue).date} — $label',
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildDepTagNextDue(DependencyTagHabitSpec spec) {
    final completions = widget.habit.completions;
    int sinceLastCompletion;

    if (completions.isEmpty) {
      sinceLastCompletion = spec.tagOccurrences.length;
    } else {
      final lastCompletion = completions.reduce((a, b) => a.isAfter(b) ? a : b);
      sinceLastCompletion = spec.tagOccurrences
          .where((t) => t.isAfter(lastCompletion))
          .length;
    }

    final remaining = spec.requiredCount - sinceLastCompletion;

    if (remaining <= 0) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.event, color: Colors.amber.shade700),
          title: const Text('Next Due'),
          subtitle: Text(
            'Due now',
            style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available, color: Colors.green),
        title: const Text('Next Due'),
        subtitle: Text(
          'Due after $remaining more ${spec.tag}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Strength Meters
  // ------------------------------------------------------------------

  double _calculateStrength(int periodDays) {
    final today = _startOfDay(DateTime.now());
    final spec = widget.habit.spec;
    final allCompletions = List<DateTime>.from(widget.habit.completions)..sort();

    DateTime startDay;
    if (periodDays == 0) {
      if (allCompletions.isEmpty) return 0;
      startDay = _startOfDay(allCompletions.first);
    } else {
      startDay = today.subtract(Duration(days: periodDays - 1));
      if (allCompletions.isNotEmpty) {
        final first = _startOfDay(allCompletions.first);
        if (startDay.isBefore(first)) startDay = first;
      }
    }

    int totalDue = 0;
    int satisfiedDue = 0;

    for (var day = startDay;
        !day.isAfter(today);
        day = day.add(const Duration(days: 1))) {
      final completionsUpToDay =
          allCompletions.where((c) => _startOfDay(c).compareTo(day) <= 0).toList();

      final isDue = spec.isDueOnDay(day, completionsUpToDay);
      if (!isDue && spec.requiredOnDay(day, completionsUpToDay) == 0) continue;

      if (isDue || spec.completedOnDay(day, allCompletions) > 0) {
        totalDue++;
        if (!isDue) {
          satisfiedDue++;
        } else if (spec.completedOnDay(day, allCompletions) > 0) {
          final completed = spec.completedOnDay(day, allCompletions);
          final required = spec.requiredOnDay(day, completionsUpToDay);
          if (required > 0 && completed >= required) {
            satisfiedDue++;
          }
        }
      }
    }

    if (totalDue == 0) return 1.0;
    return satisfiedDue / totalDue;
  }

  Widget _buildStrengthMeters() {
    final periods = [
      ('Week', 7),
      ('Month', 30),
      ('Year', 365),
      ('All-time', 0),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Strength',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (label, days) in periods) ...[
              _buildStrengthRow(label, _calculateStrength(days)),
              if (label != 'All-time') const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthRow(String label, double value) {
    final pct = (value * 100).round();
    Color color;
    if (value < 0.5) {
      color = Colors.red;
    } else if (value < 0.8) {
      color = Colors.amber.shade700;
    } else {
      color = Colors.green;
    }

    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.grey[200],
              color: color,
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Calendar
  // ------------------------------------------------------------------

  Widget _buildCalendar() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon
    final today = _startOfDay(DateTime.now());

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header with arrows
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _calendarMonth = DateTime(year, month - 1, 1);
                  }),
                ),
                Text(
                  '${months[month - 1]} $year',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _calendarMonth = DateTime(year, month + 1, 1);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Weekday headers
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600])),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            // Day grid
            ..._buildCalendarWeeks(
                year, month, daysInMonth, firstWeekday, today),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCalendarWeeks(
      int year, int month, int daysInMonth, int firstWeekday, DateTime today) {
    final weeks = <Widget>[];
    final allCompletions = List<DateTime>.from(widget.habit.completions)..sort();
    var dayNum = 1;

    final offset = firstWeekday - 1;

    while (dayNum <= daysInMonth) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final cellIndex = (weeks.length * 7) + col;
        if (cellIndex < offset || dayNum > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 36)));
          continue;
        }

        final day = DateTime(year, month, dayNum);
        cells.add(Expanded(child: _buildCalendarCell(day, today, allCompletions)));
        dayNum++;
      }
      weeks.add(Row(children: cells));
    }
    return weeks;
  }

  Widget _buildCalendarCell(
      DateTime day, DateTime today, List<DateTime> allCompletions) {
    final isFuture = day.isAfter(today);
    final spec = widget.habit.spec;

    final completionsUpToDay =
        allCompletions.where((c) => _startOfDay(c).compareTo(day) <= 0).toList();
    final isDue = spec.isDueOnDay(day, completionsUpToDay) ||
        spec.requiredOnDay(day, completionsUpToDay) > 0;
    final completed = spec.completedOnDay(day, allCompletions);

    Widget content;

    if (completed > 0) {
      // Completed — green circle with checkmark, tappable to remove
      content = GestureDetector(
        onTap: isFuture ? null : () => _removeCompletion(day),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.check, size: 16, color: Colors.green.shade700),
            ),
            if (completed > 1)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: Text(
                    '$completed',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (isFuture && isDue) {
      // Future due — faint outline circle (no interaction)
      content = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text('${day.day}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    } else if (isFuture) {
      // Future, not due — grey number (no interaction)
      content = Text(
        '${day.day}',
        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
      );
    } else {
      // Past/today, no completion — plain day number, tappable to add
      content = GestureDetector(
        onTap: () => _addCompletion(day),
        child: Text(
          '${day.day}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: Center(child: content),
    );
  }

  // ------------------------------------------------------------------
  // Calendar interactions
  // ------------------------------------------------------------------

  Future<void> _addCompletion(DateTime day) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (time == null || !mounted) return;

    final timestamp = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final dateLabel = DateTimeFormatter(day).date;
    final timeLabel = time.format(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add completion'),
        content: Text('Add completion on $dateLabel at $timeLabel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.onAddEntryWithTimestamp(widget.habit.fullText, timestamp);
    if (mounted) setState(() {});
  }

  Future<void> _removeCompletion(DateTime day) async {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final habit = widget.habit;

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

    if (toDelete == null) return;

    final dateLabel = DateTimeFormatter(day).date;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove completion'),
        content: Text('Remove most recent completion on $dateLabel?'),
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

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit.displayName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.habit.spec.displayLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          _buildSummaryCard(context),
          const SizedBox(height: 16),
          _buildNextDue(),
          const SizedBox(height: 16),
          _buildStrengthMeters(),
          const SizedBox(height: 16),
          _buildSectionTitle(context, 'Completions'),
          const SizedBox(height: 8),
          _buildCalendar(),
        ],
      ),
    );
  }
}
