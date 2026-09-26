import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../utils.dart';
import '../habit_logic.dart';
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
  @override
  void initState() {
    super.initState();
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

    // Negative habits are never due
    if (_isNegativeSpec(spec)) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.block, color: Colors.green),
          title: const Text('Avoidance Habit'),
          subtitle: const Text('Goal: keep occurrences at zero'),
        ),
      );
    }

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
    // Banked occurrences, including any surplus carried over from the last
    // cycle, so this matches when the habit actually comes due.
    final banked = spec.creditsOnDay(DateTime.now(), widget.habit.completions);
    final remaining = spec.requiredCount - banked;

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
          'Due after $remaining more ${spec.tag}'
          '${banked > 0 ? ' ($banked of ${spec.requiredCount} logged)' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Strength Meters
  // ------------------------------------------------------------------

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
            Text(
                _isNegativeSpec(widget.habit.spec) ? 'Avoidance' : 'Strength',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (label, days) in periods) ...[
              _buildStrengthRow(label, calculateHabitStrength(widget.habit.spec, widget.habit.completions, periodDays: days)),
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
    final today = _startOfDay(DateTime.now());
    final allCompletions = List<DateTime>.from(widget.habit.completions)..sort();

    // Build a set of completion counts by day for quick lookup
    final completionCounts = <DateTime, int>{};
    for (final c in allCompletions) {
      final d = _startOfDay(c);
      completionCounts[d] = (completionCounts[d] ?? 0) + 1;
    }

    // Number of weeks to show (roughly 6 months)
    const totalWeeks = 26;

    // Find the Sunday that ends the current week (today's week)
    // weekday: 1=Mon .. 7=Sun
    final endDate = today.add(Duration(days: 7 - today.weekday));
    final startDate = endDate.subtract(Duration(days: totalWeeks * 7 - 1));

    // Build month labels with their column positions
    final monthLabels = <({String label, int col})>[];
    int? lastMonth;
    for (int col = 0; col < totalWeeks; col++) {
      final weekStart = startDate.add(Duration(days: col * 7));
      if (weekStart.month != lastMonth) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        monthLabels.add((label: months[weekStart.month - 1], col: col));
        lastMonth = weekStart.month;
      }
    }

    const double cellSize = 14;
    const double cellGap = 3;
    const double labelWidth = 20; // width for day-of-week labels

    final scrollController = ScrollController(
      initialScrollOffset: (totalWeeks * (cellSize + cellGap)).toDouble(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month labels row
            SizedBox(
              height: 16,
              child: Row(
                children: [
                  SizedBox(width: labelWidth),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: ScrollController(
                        initialScrollOffset: (totalWeeks * (cellSize + cellGap)).toDouble(),
                      ),
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalWeeks * (cellSize + cellGap),
                        child: Stack(
                          children: monthLabels.map((m) => Positioned(
                            left: m.col * (cellSize + cellGap),
                            child: Text(m.label,
                              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          )).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Heatmap grid
            SizedBox(
              height: 7 * (cellSize + cellGap) - cellGap,
              child: Row(
                children: [
                  // Day-of-week labels
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['M', '', 'W', '', 'F', '', 'S']
                          .map((d) => SizedBox(
                                height: cellSize,
                                child: Center(
                                  child: Text(d,
                                      style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  // Scrollable grid
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(totalWeeks, (col) {
                          return Padding(
                            padding: EdgeInsets.only(right: cellGap),
                            child: Column(
                              children: List.generate(7, (row) {
                                final day = startDate.add(Duration(days: col * 7 + row));
                                final isFuture = day.isAfter(today);
                                final count = completionCounts[_startOfDay(day)] ?? 0;

                                return Padding(
                                  padding: EdgeInsets.only(bottom: row < 6 ? cellGap : 0),
                                  child: GestureDetector(
                                    onTap: isFuture ? null : () {
                                      if (count > 0) {
                                        _removeCompletion(day);
                                      } else {
                                        _addCompletion(day);
                                      }
                                    },
                                    child: Tooltip(
                                      message: '${DateTimeFormatter(day).date}${count > 0 ? ' ($count)' : ''}',
                                      child: Container(
                                        width: cellSize,
                                        height: cellSize,
                                        decoration: BoxDecoration(
                                          color: _heatmapColor(day, today, count),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _heatmapColor(DateTime day, DateTime today, int count) {
    if (day.isAfter(today)) return Colors.grey.shade100;

    final isNegative = _isNegativeSpec(widget.habit.spec);

    if (isNegative) {
      // Negative habits: green = no occurrences (good), red = occurred (bad)
      if (count == 0) return Colors.green.shade200;
      if (count == 1) return Colors.red.shade200;
      return Colors.red.shade400;
    }

    if (count == 0) return Colors.grey.shade200;
    if (count == 1) return Colors.green.shade300;
    if (count == 2) return Colors.green.shade500;
    return Colors.green.shade700;
  }

  bool _isNegativeSpec(HabitSpec spec) =>
      spec is NegativeHabitSpec || spec is NegativeTagHabitSpec;


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
    if (mounted) {
      HapticFeedback.mediumImpact();
      setState(() {});
    }
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
