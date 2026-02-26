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
