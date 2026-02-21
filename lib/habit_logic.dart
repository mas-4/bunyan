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

/// Compute the number of days until the habit is next due.
///
/// Returns 0 if due today, 1 if due tomorrow, etc.
/// Returns 999 if not due within the next year.
int nextDueDayIndex(
  HabitSpec spec,
  List<DateTime> completions, {
  DateTime? today,
}) {
  today ??= DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  for (int i = 0; i <= 366; i++) {
    final day = todayStart.add(Duration(days: i));
    if (spec.isDueOnDay(day, completions)) return i;
  }
  return 999;
}

/// Extract the first #tag from a habit's display name.
///
/// Returns null if no tag is found.
String? extractFirstTag(String displayName) {
  final match = RegExp(r'#\S+').firstMatch(displayName);
  return match?.group(0);
}
