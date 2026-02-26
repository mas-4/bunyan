import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';

import '../models.dart';
import '../utils.dart';

class _CalendarEntry {
  final WordEntry entry;
  final DateTime calendarDate;
  final bool hasWhenTag;

  _CalendarEntry({required this.entry, required this.calendarDate, required this.hasWhenTag});
}

class CalendarScreen extends StatefulWidget {
  final List<WordEntry> entries;

  const CalendarScreen({super.key, required this.entries});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _selectedMonth;
  late DateTime _selectedDay;
  List<_CalendarEntry> _calendarEntries = [];
  Map<String, List<_CalendarEntry>> _entriesByDate = {};
  int _slideDirection = 1; // 1 = forward, -1 = back

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _buildCalendarEntries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildCalendarEntries() {
    _calendarEntries = [];
    for (final entry in widget.entries) {
      final whenDates = extractWhenDates(entry.word);
      if (whenDates.isNotEmpty) {
        for (final date in whenDates) {
          _calendarEntries.add(_CalendarEntry(entry: entry, calendarDate: date, hasWhenTag: true));
        }
      } else {
        _calendarEntries.add(_CalendarEntry(entry: entry, calendarDate: entry.timestamp, hasWhenTag: false));
      }
    }
    _calendarEntries.sort((a, b) => a.calendarDate.compareTo(b.calendarDate));

    _entriesByDate = {};
    for (final ce in _calendarEntries) {
      final key = _dateKey(ce.calendarDate);
      _entriesByDate.putIfAbsent(key, () => []);
      _entriesByDate[key]!.add(ce);
    }
  }

  String _dateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  List<_CalendarEntry> _entriesForDay(DateTime day) {
    return _entriesByDate[_dateKey(day)] ?? [];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _isOnCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _prevMonth() {
    setState(() {
      _slideDirection = -1;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _slideDirection = 1;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Calendar help',
            onPressed: _showCalendarHelp,
          ),
          if (!_isOnCurrentMonth)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Jump to today',
              onPressed: _jumpToToday,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Month'),
            Tab(text: 'Upcoming'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildMonthTab(),
          _buildAllEventsTab(),
        ],
      ),
    );
  }

  // --- Month Tab ---
  Widget _buildMonthTab() {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Sunday = 0 start
    final startWeekday = firstDay.weekday % 7; // Mon=1..Sun=7 -> Sun=0,Mon=1..Sat=6
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < 0) {
            _nextMonth();
          } else if (details.primaryVelocity! > 0) {
            _prevMonth();
          }
        }
      },
      child: Column(
      children: [
        // Month header (stays static)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevMonth),
              Text(
                '${months[month - 1]} $year',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
            ],
          ),
        ),
        // Animated month content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              // Determine slide direction based on whether this is the incoming or outgoing child
              final isIncoming = child.key == ValueKey(_selectedMonth);
              final beginOffset = isIncoming
                  ? Offset(_slideDirection.toDouble(), 0)
                  : Offset(-_slideDirection.toDouble(), 0);
              return SlideTransition(
                position: Tween<Offset>(
                  begin: beginOffset,
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
                child: child,
              );
            },
            child: Column(
              key: ValueKey(_selectedMonth),
              children: [
                // Weekday labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                        .map((d) => Expanded(
                              child: Center(
                                child: Text(d, style: Theme.of(context).textTheme.bodySmall),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 4),
                // Day grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(startWeekday + daysInMonth, (index) {
                      if (index < startWeekday) {
                        return const SizedBox();
                      }
                      final day = index - startWeekday + 1;
                      final date = DateTime(year, month, day);
                      final hasEntries = _entriesForDay(date).isNotEmpty;
                      final isSelected = _isSameDay(date, _selectedDay);
                      final isToday = _isSameDay(date, today);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDay = date;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withAlpha(50)
                                : null,
                            border: isToday
                                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (hasEntries)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const Divider(),
                // Selected day entries
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatDayHeader(_selectedDay),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                Expanded(child: _buildEntryList(_entriesForDay(_selectedDay))),
              ],
            ),
          ),
        ),
      ],
    ),
    );
  }

  // --- Upcoming Events Tab ---

  /// Compute next due dates for calendar-based habits (weekday, monthly, yearly).
  List<({String name, String spec, DateTime date})> _buildUpcomingHabits() {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final result = <({String name, String spec, DateTime date})>[];

    // Build habit map (same logic as habit_screen)
    final habitMap = <String, ({String name, HabitSpec spec, List<DateTime> completions})>{};
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
      habitMap[hash] = (name: content, spec: spec, completions: completions);
    }

    for (final habit in habitMap.values) {
      if (habit.spec is DiscontinuedHabitSpec) continue;

      // Only include calendar-based specs (and composites containing them)
      final specs = habit.spec is CompositeHabitSpec
          ? (habit.spec as CompositeHabitSpec).specs
          : [habit.spec];

      final isCalendarBased = specs.any((s) =>
          s is WeekdayHabitSpec ||
          s is MonthlyDateHabitSpec ||
          s is YearlyDateHabitSpec ||
          s is YearlyMonthHabitSpec);
      if (!isCalendarBased) continue;

      // Find next due date within 366 days
      for (int i = 0; i <= 366; i++) {
        final day = todayStart.add(Duration(days: i));
        if (habit.spec.isDueOnDay(day, habit.completions)) {
          result.add((name: habit.name, spec: habit.spec.displayLabel, date: day));
          break;
        }
      }
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  Widget _buildAllEventsTab() {
    final now = DateTime.now();

    // #when entries in the future
    final upcomingByDate = <String, List<dynamic>>{};
    for (final ce in _calendarEntries) {
      if (!ce.hasWhenTag) continue;
      if (ce.calendarDate.isBefore(now)) continue;
      final key = _dateKey(ce.calendarDate);
      upcomingByDate.putIfAbsent(key, () => []);
      upcomingByDate[key]!.add(ce);
    }

    // Upcoming habit due dates
    final upcomingHabits = _buildUpcomingHabits();
    for (final habit in upcomingHabits) {
      final key = _dateKey(habit.date);
      upcomingByDate.putIfAbsent(key, () => []);
      upcomingByDate[key]!.add(habit);
    }

    final sortedKeys = upcomingByDate.keys.toList()..sort();

    if (sortedKeys.isEmpty) {
      return const Center(child: Text('No upcoming events'));
    }

    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final key = sortedKeys[index];
        final items = upcomingByDate[key]!;
        final parts = key.split('-');
        final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _formatDayHeader(date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...items.map((item) {
              if (item is _CalendarEntry) {
                return _buildCalendarEntryTile(item, hideWhenTag: true);
              } else {
                final habit = item as ({String name, String spec, DateTime date});
                return ListTile(
                  leading: Icon(Icons.loop, size: 18, color: Colors.grey.shade600),
                  title: Text(habit.name),
                  subtitle: Text(habit.spec),
                  dense: true,
                );
              }
            }),
            if (index < sortedKeys.length - 1) const Divider(),
          ],
        );
      },
    );
  }

  // --- Shared helpers ---
  String _formatDayHeader(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildEntryList(List<_CalendarEntry> entries) {
    if (entries.isEmpty) {
      return const Center(child: Text('No entries this day', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildCalendarEntryTile(entries[index]),
    );
  }

  void _addToSystemCalendar(_CalendarEntry ce) {
    final displayText = ce.entry.word.replaceAll(whenTagRegex, '').trim();
    final event = Event(
      title: displayText,
      startDate: ce.calendarDate,
      endDate: ce.calendarDate.add(const Duration(hours: 1)),
    );
    Add2Calendar.addEvent2Cal(event);
  }

  void _showCalendarHelp() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Calendar Tags', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text(
              'Use #when to attach a date/time to any entry. '
              'Typing #when auto-opens a date & time picker.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#when[2026-02-16 2:30:00 PM]',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Entries with #when tags appear on the calendar and show '
              'a button to export to your system calendar.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Calendar-anchored habits (e.g. @habit[every monday]) also '
              'appear in the Upcoming tab.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarEntryTile(_CalendarEntry ce, {bool hideWhenTag = false}) {
    final dt = DateTimeFormatter(ce.calendarDate);
    final displayText = hideWhenTag
        ? ce.entry.word.replaceAll(whenTagRegex, '').trim()
        : ce.entry.word.replaceAll(whenTagRegex, '#when').trim();
    return ListTile(
      title: Text(displayText),
      subtitle: Text(dt.time),
      leading: ce.hasWhenTag
          ? Icon(Icons.event, size: 18, color: Theme.of(context).colorScheme.primary)
          : null,
      trailing: ce.hasWhenTag
          ? IconButton(
              icon: Icon(Icons.notification_add, size: 20),
              tooltip: 'Add to system calendar',
              onPressed: () => _addToSystemCalendar(ce),
            )
          : null,
      dense: true,
    );
  }
}
