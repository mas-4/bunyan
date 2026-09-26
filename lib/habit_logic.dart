import 'utils.dart';

/// Compute strength (completion rate) for a habit.
///
/// [periodDays] == 0 means all-time (from first completion to today).
/// [periodDays] > 0 means look back that many days (clamped to first completion).
/// [today] defaults to DateTime.now() — pass explicitly for deterministic tests.
double calculateHabitStrength(
  HabitSpec spec,
  List<DateTime> completions, {
  int periodDays = 0,
  DateTime? today,
}) {
  today ??= DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  // Negative habits: strength = days WITHOUT occurrences / total days
  if (spec is NegativeHabitSpec || spec is NegativeTagHabitSpec) {
    return _calculateNegativeStrength(spec, completions, periodDays: periodDays, todayStart: todayStart);
  }

  final allCompletions = List<DateTime>.from(completions)..sort();

  // Specs whose obligation spans a window (3/w, 1/m, november, ...) are
  // scored per window, not per day — otherwise every day of an unfinished
  // window counts as a miss.
  if (_hasPeriods(spec, allCompletions, todayStart)) {
    return _calculatePeriodicStrength(
      spec,
      allCompletions,
      periodDays: periodDays,
      todayStart: todayStart,
    );
  }

  DateTime startDay;
  if (periodDays == 0) {
    if (allCompletions.isEmpty) return 0;
    startDay = DateTime(
      allCompletions.first.year,
      allCompletions.first.month,
      allCompletions.first.day,
    );
  } else {
    startDay = todayStart.subtract(Duration(days: periodDays - 1));
    if (allCompletions.isNotEmpty) {
      final first = DateTime(
        allCompletions.first.year,
        allCompletions.first.month,
        allCompletions.first.day,
      );
      if (startDay.isBefore(first)) startDay = first;
    }
  }

  int totalDue = 0;
  int satisfiedDue = 0;

  for (var day = startDay;
      !day.isAfter(todayStart);
      day = day.add(const Duration(days: 1))) {
    final completionsUpToDay = allCompletions
        .where((c) =>
            DateTime(c.year, c.month, c.day).compareTo(day) <= 0)
        .toList();

    final isDue = spec.isDueOnDay(day, completionsUpToDay);
    final completed = spec.completedOnDay(day, allCompletions);
    // A day the habit was done on counts even when the spec no longer reports
    // it as due — for interval habits `requiredOnDay` mirrors `isDueOnDay`,
    // so skipping those days left only missed days in the tally.
    if (!isDue &&
        completed == 0 &&
        spec.requiredOnDay(day, completionsUpToDay) == 0) {
      continue;
    }

    if (isDue || completed > 0) {
      totalDue++;
      if (!isDue) {
        satisfiedDue++;
      } else if (completed > 0) {
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

/// Whether [spec] scores in windows longer than a day anywhere in the
/// range being measured.
bool _hasPeriods(HabitSpec spec, List<DateTime> completions, DateTime todayStart) {
  if (spec.periodBounds(todayStart) != null) return true;
  // A window spec may not apply today (a november habit in June), so probe
  // the completions too.
  for (final c in completions) {
    if (spec.periodBounds(DateTime(c.year, c.month, c.day)) != null) return true;
  }
  return false;
}

/// Completion rate over windows: each window counts once, and a window that
/// is still open only counts once it has been satisfied.
double _calculatePeriodicStrength(
  HabitSpec spec,
  List<DateTime> sortedCompletions, {
  required int periodDays,
  required DateTime todayStart,
}) {
  DateTime startDay;
  if (periodDays == 0) {
    if (sortedCompletions.isEmpty) return 0;
    final first = sortedCompletions.first;
    startDay = DateTime(first.year, first.month, first.day);
  } else {
    startDay = todayStart.subtract(Duration(days: periodDays - 1));
    if (sortedCompletions.isNotEmpty) {
      final first = sortedCompletions.first;
      final firstDay = DateTime(first.year, first.month, first.day);
      if (startDay.isBefore(firstDay)) startDay = firstDay;
    }
  }

  int totalPeriods = 0;
  int satisfiedPeriods = 0;
  final seen = <String>{};

  for (var day = startDay;
      !day.isAfter(todayStart);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final bounds = spec.periodBounds(day);
    if (bounds == null) continue; // day carries no obligation
    if (!seen.add(bounds.start.toIso8601String())) continue;

    var required = spec.requiredInPeriod(day);
    if (required <= 0) continue;

    // A window the range only partly covers (the one the habit started in)
    // is prorated so a habit created mid-week doesn't open at 0%.
    if (bounds.start.isBefore(startDay)) {
      final total = bounds.end.difference(bounds.start).inDays;
      final available = bounds.end.difference(startDay).inDays;
      if (total > 0 && available > 0 && available < total) {
        final scaled = (required * available / total).round();
        required = scaled < 1 ? 1 : scaled;
      }
    }

    final done = sortedCompletions
        .where((c) => !c.isBefore(bounds.start) && c.isBefore(bounds.end))
        .length;
    final stillOpen = bounds.end.isAfter(todayStart);

    if (done >= required) {
      totalPeriods++;
      satisfiedPeriods++;
    } else if (!stillOpen) {
      totalPeriods++;
    }
  }

  if (totalPeriods == 0) return 1.0;
  return satisfiedPeriods / totalPeriods;
}

double _calculateNegativeStrength(
  HabitSpec spec,
  List<DateTime> completions, {
  required int periodDays,
  required DateTime todayStart,
}) {
  // For NegativeTagHabitSpec, occurrences come from tagOccurrences;
  // for NegativeHabitSpec, occurrences are the completions themselves.
  final occurrences = List<DateTime>.from(
      spec is NegativeTagHabitSpec ? spec.tagOccurrences : completions)
    ..sort();

  if (occurrences.isEmpty) return 1.0;

  DateTime startDay;
  if (periodDays == 0) {
    startDay = DateTime(
      occurrences.first.year,
      occurrences.first.month,
      occurrences.first.day,
    );
  } else {
    startDay = todayStart.subtract(Duration(days: periodDays - 1));
    final first = DateTime(
      occurrences.first.year,
      occurrences.first.month,
      occurrences.first.day,
    );
    if (startDay.isBefore(first)) startDay = first;
  }

  int totalDays = 0;
  int cleanDays = 0;

  // Use explicit date construction to avoid DST issues with Duration(days: 1)
  for (var day = startDay;
      !day.isAfter(todayStart);
      day = DateTime(day.year, day.month, day.day + 1)) {
    totalDays++;
    final count = occurrences.where((c) =>
        DateTime(c.year, c.month, c.day) == day).length;
    if (count == 0) cleanDays++;
  }

  if (totalDays == 0) return 1.0;
  return cleanDays / totalDays;
}

/// Compute the number of days until the habit is next due.
///
/// Returns 0 if due today, 1 if due tomorrow, etc.
/// Returns 999 if not due within the next year.
int nextDueDayIndex(
  HabitSpec spec,
  List<DateTime> completions, {
  DateTime? today,
}) {
  // Negative habits are never "due"
  if (spec is NegativeHabitSpec || spec is NegativeTagHabitSpec) return 999;

  today ??= DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  for (int i = 0; i <= 366; i++) {
    final day = todayStart.add(Duration(days: i));
    if (spec.isDueOnDay(day, completions)) return i;
  }
  return 999;
}

/// Calculate the current streak of consecutive due-days completed,
/// walking backwards from today.
///
/// Off-days (where the habit isn't due) are skipped and don't break the streak.
/// Returns 0 if the most recent due day was missed.
int calculateCurrentStreak(
  HabitSpec spec,
  List<DateTime> completions, {
  DateTime? today,
}) {
  // Negative habits don't have streaks
  if (spec is NegativeHabitSpec || spec is NegativeTagHabitSpec) return 0;

  today ??= DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  final allCompletions = List<DateTime>.from(completions)..sort();
  if (allCompletions.isEmpty) return 0;

  if (_hasPeriods(spec, allCompletions, todayStart)) {
    return _calculatePeriodicStreak(spec, allCompletions, todayStart);
  }

  int streak = 0;

  for (int i = 0; i <= 366; i++) {
    final day = DateTime(todayStart.year, todayStart.month, todayStart.day - i);
    final completionsUpToDay = allCompletions
        .where((c) => DateTime(c.year, c.month, c.day).compareTo(day) <= 0)
        .toList();
    final isDue = spec.isDueOnDay(day, completionsUpToDay);

    if (!isDue) continue; // Skip off-days

    final completed = spec.completedOnDay(day, allCompletions);
    if (completed > 0) {
      streak++;
    } else if (day == todayStart) {
      continue; // Today not yet completed — don't break streak
    } else {
      break; // Streak broken
    }
  }

  return streak;
}

/// Extract the first #tag from a habit's display name.
///
/// Returns null if no tag is found.
String? extractFirstTag(String displayName) {
  final match = RegExp(r'#\S+').firstMatch(displayName);
  return match?.group(0);
}

/// Consecutive satisfied windows, walking back from the window containing
/// today. The current window doesn't break the streak while it's still open.
int _calculatePeriodicStreak(
  HabitSpec spec,
  List<DateTime> sortedCompletions,
  DateTime todayStart,
) {
  final first = sortedCompletions.first;
  final firstDay = DateTime(first.year, first.month, first.day);

  int streak = 0;
  var cursor = todayStart;

  for (int guard = 0; guard < 800; guard++) {
    if (cursor.isBefore(firstDay)) break;

    final bounds = spec.periodBounds(cursor);
    if (bounds == null) {
      // Day outside any window (a november habit in June) — keep walking.
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
      continue;
    }

    final required = spec.requiredInPeriod(cursor);
    final done = sortedCompletions
        .where((c) => !c.isBefore(bounds.start) && c.isBefore(bounds.end))
        .length;
    final stillOpen = bounds.end.isAfter(todayStart);

    if (done >= required) {
      streak++;
    } else if (!stillOpen) {
      break;
    }

    cursor = DateTime(bounds.start.year, bounds.start.month, bounds.start.day - 1);
  }

  return streak;
}
