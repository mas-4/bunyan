import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../day_stats.dart';
import '../models.dart';
import '../utils.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _longDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

String _hourLabel(int h) {
  final suffix = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 $suffix';
}

/// One day at a glance: counts, when activity happened, tags, and a timeline.
/// Swipe sideways or use the arrows / week strip to move between days.
class DayOverviewScreen extends StatefulWidget {
  /// Read on every build so edits made from this screen show up immediately.
  final List<WordEntry> Function() getEntries;
  final DateTime initialDay;
  final Future<void> Function(WordEntry entry)? onEditEntry;
  final void Function(String word)? onOpenEntryStats;

  const DayOverviewScreen({
    super.key,
    required this.getEntries,
    required this.initialDay,
    this.onEditEntry,
    this.onOpenEntryStats,
  });

  @override
  State<DayOverviewScreen> createState() => _DayOverviewScreenState();
}

class _DayOverviewScreenState extends State<DayOverviewScreen> {
  late DateTime _day;

  DateTime get _today => dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _day = dateOnly(widget.initialDay);
  }

  void _setDay(DateTime d) => setState(() => _day = dateOnly(d));

  void _shift(int days) => _setDay(DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _setDay(picked);
  }

  String _relativeLabel() {
    final diff = DateTime.utc(_day.year, _day.month, _day.day)
        .difference(DateTime.utc(_today.year, _today.month, _today.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return diff < 0 ? '${-diff} days ago' : 'In $diff days';
  }

  Future<void> _edit(WordEntry entry) async {
    final edit = widget.onEditEntry;
    if (edit == null) return;
    await edit(entry);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.getEntries();
    final stats = computeDayStats(all, _day);
    final weekStart = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
    final weekCounts = dailyEntryCounts(all, weekStart, 7);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day overview'),
        actions: [
          if (_day != _today)
            TextButton(onPressed: () => _setDay(_today), child: const Text('Today')),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Pick a day',
            onPressed: _pickDay,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) _shift(1);
          if (v > 200) _shift(-1);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16, 4, 16, MediaQuery.of(context).padding.bottom + 24,
          ),
          children: [
            _header(context),
            const SizedBox(height: 4),
            _weekStrip(context, weekStart, weekCounts),
            const SizedBox(height: 16),
            if (stats.isEmpty)
              _emptyDay(context)
            else ...[
              _statTiles(context, stats),
              const SizedBox(height: 20),
              _sectionTitle(context, 'By hour'),
              _hourlyChart(context, stats),
              _hourlyCaption(context, stats),
            ],
            if (stats.tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, 'Tags'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in stats.tags.take(20))
                    Chip(
                      label: Text('${t.key}  ${t.value}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (stats.repeated.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, 'Logged more than once'),
              for (final r in stats.repeated.take(8))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entryDisplayText(r.key), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text('×${r.value}', style: Theme.of(context).textTheme.titleSmall),
                  onTap: widget.onOpenEntryStats == null
                      ? null
                      : () => widget.onOpenEntryStats!(r.key),
                ),
            ],
            if (stats.scheduled.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, 'Scheduled'),
              for (final s in stats.scheduled) _scheduledRow(context, s),
            ],
            if (stats.timeline.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, 'Timeline · ${stats.timeline.length}'),
              for (final e in stats.timeline) _timelineRow(context, e),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous day',
          onPressed: () => _shift(-1),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickDay,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(_longDate(_day), style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    _relativeLabel(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next day',
          onPressed: () => _shift(1),
        ),
      ],
    );
  }

  /// Mon–Sun of the selected day's week; bar height = entries that day.
  Widget _weekStrip(BuildContext context, DateTime weekStart, List<int> counts) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = counts.fold<int>(0, (a, b) => a > b ? a : b);
    const barMax = 32.0;

    return Row(
      children: List.generate(7, (i) {
        final d = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
        final selected = d == _day;
        final future = d.isAfter(_today);
        final count = counts[i];
        final barHeight = maxCount == 0 ? 0.0 : (count / maxCount) * barMax;
        final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _setDay(d),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? scheme.primaryContainer : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Opacity(
                  opacity: future ? 0.45 : 1,
                  child: Column(
                    children: [
                      Text(
                        _weekdayNames[i].substring(0, 1),
                        style: TextStyle(fontSize: 11, color: fg),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: barMax,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: 10,
                            height: count == 0 ? 2 : barHeight.clamp(3.0, barMax),
                            decoration: BoxDecoration(
                              color: count == 0
                                  ? scheme.outlineVariant
                                  : scheme.primary.withValues(alpha: selected ? 1 : 0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                      Text(
                        count == 0 ? '–' : '$count',
                        style: TextStyle(fontSize: 10, color: fg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _emptyDay(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.wb_twilight, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            _day.isAfter(_today) ? 'This day hasn\'t happened yet.' : 'Nothing logged on this day.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _statTiles(BuildContext context, DayStats s) {
    final avg = s.recentAverage;
    String? entriesSub;
    if (avg != null) {
      final delta = s.entries.length - avg;
      final sign = delta >= 0 ? '+' : '−';
      entriesSub = '$sign${delta.abs().toStringAsFixed(1)} vs ${s.averageWindowDays}d avg';
    }
    final first = s.first;
    final last = s.last;
    final span = s.activeSpan;

    final tiles = <Widget>[
      _StatTile(label: 'Entries', value: '${s.entries.length}', sub: entriesSub),
      _StatTile(label: 'Unique', value: '${s.uniqueCount}'),
      _StatTile(
        label: 'Active',
        value: span == null ? '—' : formatSpan(span),
        sub: first == null
            ? null
            : span == null
                ? DateTimeFormatter(first).time
                : '${DateTimeFormatter(first).time} – ${DateTimeFormatter(last!).time}',
      ),
      _StatTile(label: 'Habit logs', value: '${s.habitLogs}'),
      _StatTile(
        label: 'Todos done',
        value: '${s.completedTodos}',
        sub: s.newTodos > 0 ? '${s.newTodos} added' : null,
      ),
      _StatTile(label: 'Notes', value: '${s.notes}'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }

  Widget _hourlyChart(BuildContext context, DayStats s) {
    final scheme = Theme.of(context).colorScheme;
    final busiest = s.busiestHour;
    final maxY = s.hourly.fold<int>(0, (a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: maxY > 0 ? maxY * 1.15 : 1,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${_hourLabel(group.x)}: ${rod.toY.toInt()}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final h = value.toInt();
                  if (h % 6 != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _hourLabel(h).replaceAll(' ', '').toLowerCase(),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barGroups: List.generate(24, (h) {
            final v = s.hourly[h];
            return BarChartGroupData(
              x: h,
              barRods: [
                BarChartRodData(
                  toY: v.toDouble(),
                  width: 8,
                  color: h == busiest
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.45),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY > 0 ? maxY * 1.15 : 1,
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _hourlyCaption(BuildContext context, DayStats s) {
    final parts = <String>[];
    final busiest = s.busiestHour;
    if (busiest != null) {
      parts.add('Busiest around ${_hourLabel(busiest)} (${s.hourly[busiest]})');
    }
    final gap = s.longestGap;
    if (gap != null && gap.inMinutes >= 1) {
      parts.add('longest quiet stretch ${formatSpan(gap)}');
    }
    if (parts.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _scheduledRow(BuildContext context, ScheduledItem s) {
    final text = entryDisplayText(s.entry.word.replaceAll(whenTagRegex, '').trim());
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        s.done ? Icons.check_circle : Icons.event_outlined,
        color: s.done ? Colors.green : Colors.grey.shade600,
      ),
      title: Text(
        text,
        style: s.done
            ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
            : null,
      ),
      trailing: Text(DateTimeFormatter(s.at).time, style: Theme.of(context).textTheme.bodySmall),
      onTap: widget.onEditEntry == null ? null : () => _edit(s.entry),
    );
  }

  Widget _timelineRow(BuildContext context, WordEntry e) {
    final theme = Theme.of(context);
    final done = isDoneText(e.word);
    final IconData? icon = done
        ? Icons.check_circle_outline
        : isNoteText(e.word)
            ? Icons.sticky_note_2_outlined
            : isHabitEntry(e.word)
                ? Icons.loop
                : isTodoText(e.word)
                    ? Icons.radio_button_unchecked
                    : null;

    return InkWell(
      onTap: widget.onEditEntry == null ? null : () => _edit(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                DateTimeFormatter(e.timestamp).time,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
            SizedBox(
              width: 22,
              child: icon == null
                  ? null
                  : Icon(icon, size: 16, color: done ? Colors.green : Colors.grey.shade600),
            ),
            Expanded(
              child: Text(
                entryDisplayText(e.word),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: done
                    ? theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const _StatTile({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            sub ?? ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
