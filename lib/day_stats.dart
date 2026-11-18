import 'models.dart';
import 'utils.dart';

/// Midnight (local) of [d].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day ordinal, immune to DST (a local 23h/25h day still counts as 1).
int _dayIndex(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// A scheduled (`#when`) entry falling on the overview day.
typedef ScheduledItem = ({WordEntry entry, DateTime at, bool done});

/// Everything the day overview shows for one calendar day.
class DayStats {
  final DateTime day;

  /// Everything logged that day, oldest first, including `#done` records.
  final List<WordEntry> timeline;

  /// [timeline] without `#done` records — the "real" entries.
  final List<WordEntry> entries;

  final int uniqueCount;
  final int completedTodos;
  final int newTodos;
  final int habitLogs;
  final int notes;

  /// Activity (timeline) per hour of day, index 0–23.
  final List<int> hourly;

  /// Non-system tags on [entries], most used first.
  final List<MapEntry<String, int>> tags;

  /// Entry texts logged more than once that day, most repeated first.
  final List<MapEntry<String, int>> repeated;

  /// Entries whose `#when` date falls on this day, in time order.
  final List<ScheduledItem> scheduled;

  /// Mean entries per day over the [averageWindowDays] days before [day]
  /// (clipped to when logging began). Null when there's no history yet.
  final double? recentAverage;
  final int averageWindowDays;

  /// Longest stretch between two consecutive things logged that day.
  final Duration? longestGap;

  const DayStats({
    required this.day,
    required this.timeline,
    required this.entries,
    required this.uniqueCount,
    required this.completedTodos,
    required this.newTodos,
    required this.habitLogs,
    required this.notes,
    required this.hourly,
    required this.tags,
    required this.repeated,
    required this.scheduled,
    required this.recentAverage,
    required this.averageWindowDays,
    required this.longestGap,
  });

  bool get isEmpty => timeline.isEmpty;

  DateTime? get first => timeline.isEmpty ? null : timeline.first.timestamp;
  DateTime? get last => timeline.isEmpty ? null : timeline.last.timestamp;

  /// Time between the first and last thing logged; null with fewer than two.
  Duration? get activeSpan =>
      timeline.length < 2 ? null : last!.difference(first!);

  /// Hour with the most activity (earliest wins ties); null on an empty day.
  int? get busiestHour {
    if (timeline.isEmpty) return null;
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (hourly[h] > hourly[best]) best = h;
    }
    return best;
  }
}

/// Compute [DayStats] for [day] from the full entry list (any order).
DayStats computeDayStats(
  List<WordEntry> all,
  DateTime day, {
  int averageWindowDays = 28,
}) {
  final target = _dayIndex(day);
  final windowStart = target - averageWindowDays;

  final timeline = <WordEntry>[];
  final doneHashes = <String>{};
  final whenCandidates = <WordEntry>[];
  var earliest = target;
  var windowCount = 0;

  for (final e in all) {
    final idx = _dayIndex(e.timestamp);
    final done = isDoneText(e.word);
    if (idx < earliest) earliest = idx;
    if (idx == target) timeline.add(e);
    if (!done && idx >= windowStart && idx < target) windowCount++;
    if (done) {
      final parts = e.word.split(' ');
      if (parts.length >= 2) doneHashes.add(parts[1].toLowerCase());
    } else if (e.word.contains('#when[')) {
      whenCandidates.add(e);
    }
  }

  timeline.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final entries = timeline.where((e) => !isDoneText(e.word)).toList();

  final hourly = List<int>.filled(24, 0);
  for (final e in timeline) {
    hourly[e.timestamp.hour]++;
  }

  final tagCounts = <String, int>{};
  final tagDisplay = <String, String>{};
  final textCounts = <String, int>{};
  final textDisplay = <String, String>{};
  for (final e in entries) {
    for (final t in extractTags(e.word)) {
      if (isSystemTag(t)) continue;
      final k = t.toLowerCase();
      tagCounts[k] = (tagCounts[k] ?? 0) + 1;
      tagDisplay.putIfAbsent(k, () => t);
    }
    final k = e.word.trim().toLowerCase();
    textCounts[k] = (textCounts[k] ?? 0) + 1;
    textDisplay.putIfAbsent(k, () => e.word.trim());
  }

  List<MapEntry<String, int>> ranked(
    Map<String, int> counts,
    Map<String, String> display, {
    int min = 1,
  }) {
    return counts.entries
        .where((e) => e.value >= min)
        .map((e) => MapEntry(display[e.key]!, e.value))
        .toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
  }

  final scheduled = <ScheduledItem>[];
  for (final e in whenCandidates) {
    for (final at in extractWhenDates(e.word)) {
      if (_dayIndex(at) != target) continue;
      final done = isTodoText(e.word) &&
          doneHashes.contains(generateTodoHash(e.word, e.timestamp));
      scheduled.add((entry: e, at: at, done: done));
    }
  }
  scheduled.sort((a, b) => a.at.compareTo(b.at));

  Duration? longestGap;
  for (var i = 1; i < timeline.length; i++) {
    final gap = timeline[i].timestamp.difference(timeline[i - 1].timestamp);
    if (longestGap == null || gap > longestGap) longestGap = gap;
  }

  final historyStart = earliest > windowStart ? earliest : windowStart;
  final historyDays = target - historyStart;

  return DayStats(
    day: dateOnly(day),
    timeline: timeline,
    entries: entries,
    uniqueCount: textCounts.length,
    completedTodos: timeline.length - entries.length,
    newTodos: entries.where((e) => isTodoText(e.word)).length,
    habitLogs: entries.where((e) => isHabitEntry(e.word)).length,
    notes: entries.where((e) => isNoteText(e.word)).length,
    hourly: hourly,
    tags: ranked(tagCounts, tagDisplay),
    repeated: ranked(textCounts, textDisplay, min: 2),
    scheduled: scheduled,
    recentAverage: historyDays > 0 ? windowCount / historyDays : null,
    averageWindowDays: averageWindowDays,
    longestGap: longestGap,
  );
}

/// Entries (excluding `#done` records) per day for [days] days from [start].
List<int> dailyEntryCounts(List<WordEntry> all, DateTime start, int days) {
  final first = _dayIndex(start);
  final counts = List<int>.filled(days, 0);
  for (final e in all) {
    final offset = _dayIndex(e.timestamp) - first;
    if (offset >= 0 && offset < days && !isDoneText(e.word)) counts[offset]++;
  }
  return counts;
}

/// Compact duration like `3h 20m`, `45m`, `<1m`.
String formatSpan(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0 && m == 0) return '<1m';
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
