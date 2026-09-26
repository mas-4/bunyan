import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String tagLeaders = '!@#^&~+=\\|';
const int maxBackups = 5;

// ---------------------------------------------------------------------------
// Habit DSL
// ---------------------------------------------------------------------------

/// Matches `@habit[...]` (with spec) or bare `@habit` (discontinued).
final RegExp habitTagRegex = RegExp(r'@habit(?:\[[^\]]*\])?');

/// Returns true when the entry text contains an @habit tag.
bool isHabitEntry(String text) => habitTagRegex.hasMatch(text);

/// Strips the `@habit[...]` or `@habit` tag from text and trims.
String extractHabitContent(String text) {
  return text.replaceAll(habitTagRegex, '').trim();
}

/// Generates a stable 4-char hex hash from the "core content" of an entry.
/// Core content = text with `@habit[...]` stripped.
String generateContentHash(String text) {
  final core = extractHabitContent(text);
  final bytes = utf8.encode(core.toLowerCase());
  int hash = 0;
  for (final byte in bytes) {
    hash = ((hash << 5) - hash) + byte;
    hash = hash & 0x7FFFFFFF;
  }
  return hash.toRadixString(16).padLeft(4, '0').substring(0, 4);
}

/// Parse the `@habit[SPEC]` portion of a tag into a [HabitSpec].
/// Returns `null` when the tag is not a valid habit tag.
HabitSpec? parseHabitSpec(String text) {
  // Bare @habit (no brackets) → discontinued
  final bareMatch = RegExp(r'@habit(?!\[)').firstMatch(text);
  if (bareMatch != null && !text.contains('@habit[')) {
    return DiscontinuedHabitSpec();
  }

  final specMatch = RegExp(r'@habit\[([^\]]*)\]').firstMatch(text);
  if (specMatch == null) return null;
  final spec = specMatch.group(1)!.trim();
  if (spec.isEmpty) return DiscontinuedHabitSpec();

  // Comma-separated specs → parse each and combine
  if (spec.contains(',')) {
    final parts = spec.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final specs = <HabitSpec>[];
    for (final part in parts) {
      final parsed = _parseSingleSpec(part);
      if (parsed != null) specs.add(parsed);
    }
    if (specs.isEmpty) return null;
    if (specs.length == 1) return specs.first;
    return CompositeHabitSpec(specs: specs);
  }

  return _parseSingleSpec(spec);
}

HabitSpec? _parseSingleSpec(String spec) {
  // Negative with tag: -@tag, -#tag, "not @tag", "not 3 @smoke"
  final negTagMatch = RegExp(r'^-([!@#\^&~+=\\|]\S+)$').firstMatch(spec);
  if (negTagMatch != null) {
    return NegativeTagHabitSpec(tag: negTagMatch.group(1)!);
  }
  // "not [N] TAG" — the count is accepted for readability but avoidance is
  // scored per clean day, so it carries no extra meaning.
  final notTagMatch = RegExp(r'^not\s+(?:\d+\s+)?([!@#\^&~+=\\|]\S+)$',
          caseSensitive: false)
      .firstMatch(spec);
  if (notTagMatch != null) {
    return NegativeTagHabitSpec(tag: notTagMatch.group(1)!);
  }
  // Standalone negative: "-", "neg", "negative", or "not <schedule>"
  if (spec == 'negative' || spec == 'neg' || spec == '-') {
    return NegativeHabitSpec();
  }
  if (RegExp(r'^not(\s+\S+)*$', caseSensitive: false).hasMatch(spec)) {
    return NegativeHabitSpec();
  }

  // Dependency with tag: every N TAG (tag starts with a tag leader character)
  final depTagMatch = RegExp(r'^every\s+(\d+)\s+([!@#\^&~+=\\|]\S+)$', caseSensitive: false).firstMatch(spec);
  if (depTagMatch != null) {
    return DependencyTagHabitSpec(
      requiredCount: int.parse(depTagMatch.group(1)!),
      tag: depTagMatch.group(2)!,
    );
  }

  // Dependency with hash: after N HASH
  final depMatch = RegExp(r'^after\s+(\d+)\s+([a-f0-9]{4})$', caseSensitive: false).firstMatch(spec);
  if (depMatch != null) {
    return DependencyHabitSpec(
      requiredCount: int.parse(depMatch.group(1)!),
      dependencyHash: depMatch.group(2)!.toLowerCase(),
    );
  }

  // Sliding window: N in Md/Mw
  final slidingMatch = RegExp(r'^(\d+)\s+in\s+(\d+)([dwmy])$', caseSensitive: false).firstMatch(spec);
  if (slidingMatch != null) {
    return SlidingWindowHabitSpec(
      count: int.parse(slidingMatch.group(1)!),
      windowSize: int.parse(slidingMatch.group(2)!),
      windowUnit: slidingMatch.group(3)!.toLowerCase(),
    );
  }

  // Frequency: N/d, N/w, N/m, N/y
  final freqMatch = RegExp(r'^(\d+)/([dwmy])$', caseSensitive: false).firstMatch(spec);
  if (freqMatch != null) {
    return FrequencyHabitSpec(
      count: int.parse(freqMatch.group(1)!),
      periodUnit: freqMatch.group(2)!.toLowerCase(),
    );
  }

  // Interval: Nd, Nw, Nm, Ny
  final intervalMatch = RegExp(r'^(\d+)([dwmy])$', caseSensitive: false).firstMatch(spec);
  if (intervalMatch != null) {
    return IntervalHabitSpec(
      interval: int.parse(intervalMatch.group(1)!),
      unit: intervalMatch.group(2)!.toLowerCase(),
    );
  }

  // Calendar: weekday name (with or without "every" prefix)
  final weekdayMatch = RegExp(r'^(?:every\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$', caseSensitive: false).firstMatch(spec);
  if (weekdayMatch != null) {
    return WeekdayHabitSpec(dayName: weekdayMatch.group(1)!.toLowerCase());
  }

  // Calendar: month name (with or without "every" prefix)
  final monthlyMatch = RegExp(r'^(?:every\s+)?(january|february|march|april|may|june|july|august|september|october|november|december)$', caseSensitive: false).firstMatch(spec);
  if (monthlyMatch != null) {
    return YearlyMonthHabitSpec(monthName: monthlyMatch.group(1)!.toLowerCase());
  }

  // Calendar: march 13th (yearly date)
  final yearlyDateMatch = RegExp(r'^(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(?:st|nd|rd|th)$', caseSensitive: false).firstMatch(spec);
  if (yearlyDateMatch != null) {
    return YearlyDateHabitSpec(
      monthName: yearlyDateMatch.group(1)!.toLowerCase(),
      day: int.parse(yearlyDateMatch.group(2)!),
    );
  }

  // Calendar: 13th (monthly date)
  final monthlyDateMatch = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)$', caseSensitive: false).firstMatch(spec);
  if (monthlyDateMatch != null) {
    return MonthlyDateHabitSpec(day: int.parse(monthlyDateMatch.group(1)!));
  }

  return null;
}

// ---------------------------------------------------------------------------
// HabitSpec abstract class & subclasses
// ---------------------------------------------------------------------------

abstract class HabitSpec {
  /// Whether the habit is due on [day] given prior [completions].
  bool isDueOnDay(DateTime day, List<DateTime> completions);

  /// How many completions are required on [day].
  int requiredOnDay(DateTime day, List<DateTime> completions);

  /// How many of the [completions] count toward [day].
  int completedOnDay(DateTime day, List<DateTime> completions);

  /// Short label for display, e.g. "every 2d", "3/w".
  String get displayLabel;

  /// The scoring window [day] belongs to, for specs whose obligation spans
  /// more than one day (`3/w`, `1/m`, `november`, ...). `start` is inclusive,
  /// `end` exclusive.
  ///
  /// Returns null when the spec is scored day by day (the default), or when
  /// [day] carries no obligation at all (e.g. a `november` habit in June).
  /// Callers use this so a habit isn't marked missed on every day of a window
  /// it can still be completed in.
  ({DateTime start, DateTime end})? periodBounds(DateTime day) => null;

  /// How many completions the window containing [day] requires.
  /// Only meaningful when [periodBounds] is non-null.
  int requiredInPeriod(DateTime day) => 1;
}

/// Last calendar day of [month] in [year] (28-31).
int daysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

class IntervalHabitSpec extends HabitSpec {
  final int interval;
  final String unit; // d, w, m, y

  IntervalHabitSpec({required this.interval, required this.unit});

  int get _intervalDays {
    switch (unit) {
      case 'w': return interval * 7;
      case 'm': return interval * 30;
      case 'y': return interval * 365;
      default: return interval;
    }
  }

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    if (completions.isEmpty) return true;
    final sorted = List<DateTime>.from(completions)..sort();
    final lastCompletion = _startOfDay(sorted.last);
    final diff = dayStart.difference(lastCompletion).inDays;
    return diff >= _intervalDays;
  }

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => isDueOnDay(day, completions) ? 1 : 0;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  /// Whether [day] is covered by a completion within the interval.
  bool isCoveredOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    for (final c in completions) {
      final cDay = _startOfDay(c);
      final diff = dayStart.difference(cDay).inDays;
      if (diff >= 0 && diff < _intervalDays) return true;
    }
    return false;
  }

  @override
  String get displayLabel => '$interval$unit';
}

class FrequencyHabitSpec extends HabitSpec {
  final int count;
  final String periodUnit; // d, w, m, y

  FrequencyHabitSpec({required this.count, required this.periodUnit});

  @override
  ({DateTime start, DateTime end})? periodBounds(DateTime day) =>
      periodUnit == 'd' ? null : _periodBounds(day);

  @override
  int requiredInPeriod(DateTime day) => count;

  ({DateTime start, DateTime end}) _periodBounds(DateTime day) {
    final dayStart = _startOfDay(day);
    switch (periodUnit) {
      case 'w':
        final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - 1));
        return (start: weekStart, end: weekStart.add(Duration(days: 7)));
      case 'm':
        final monthStart = DateTime(dayStart.year, dayStart.month, 1);
        final monthEnd = DateTime(dayStart.year, dayStart.month + 1, 1);
        return (start: monthStart, end: monthEnd);
      case 'y':
        return (start: DateTime(dayStart.year, 1, 1), end: DateTime(dayStart.year + 1, 1, 1));
      default: // d
        return (start: dayStart, end: dayStart.add(Duration(days: 1)));
    }
  }

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    final bounds = _periodBounds(day);
    final countInPeriod = completions.where((c) =>
      !c.isBefore(bounds.start) && c.isBefore(bounds.end)).length;
    return countInPeriod < count;
  }

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => count;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => '$count/$periodUnit';
}

class SlidingWindowHabitSpec extends HabitSpec {
  final int count;
  final int windowSize;
  final String windowUnit; // d, w, m, y

  SlidingWindowHabitSpec({required this.count, required this.windowSize, required this.windowUnit});

  int get _windowDays {
    switch (windowUnit) {
      case 'w': return windowSize * 7;
      case 'm': return windowSize * 30;
      case 'y': return windowSize * 365;
      default: return windowSize;
    }
  }

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    final windowStart = dayStart.subtract(Duration(days: _windowDays - 1));
    final countInWindow = completions.where((c) {
      final cd = _startOfDay(c);
      return !cd.isBefore(windowStart) && !cd.isAfter(dayStart);
    }).length;
    return countInWindow < count;
  }

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => count;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => '$count in $windowSize$windowUnit';
}

class WeekdayHabitSpec extends HabitSpec {
  final String dayName;

  WeekdayHabitSpec({required this.dayName});

  static const _dayMap = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  int get _weekday => _dayMap[dayName] ?? 1;

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    if (day.weekday != _weekday) return false;
    final dayStart = _startOfDay(day);
    return !completions.any((c) => _startOfDay(c) == dayStart);
  }

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => day.weekday == _weekday ? 1 : 0;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => dayName.substring(0, 3);
}

class MonthlyDateHabitSpec extends HabitSpec {
  final int day;

  MonthlyDateHabitSpec({required this.day});

  /// The day this falls on in [date]'s month, clamped to the last day of
  /// short months so `31st` still lands in February.
  int _effectiveDay(DateTime date) {
    final last = daysInMonth(date.year, date.month);
    return day > last ? last : day;
  }

  @override
  bool isDueOnDay(DateTime date, List<DateTime> completions) {
    if (date.day != _effectiveDay(date)) return false;
    final dayStart = _startOfDay(date);
    return !completions.any((c) => _startOfDay(c) == dayStart);
  }

  @override
  int requiredOnDay(DateTime date, List<DateTime> completions) =>
      date.day == _effectiveDay(date) ? 1 : 0;

  @override
  int completedOnDay(DateTime date, List<DateTime> completions) {
    final dayStart = _startOfDay(date);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => '${day}th';
}

class YearlyDateHabitSpec extends HabitSpec {
  final String monthName;
  final int day;

  YearlyDateHabitSpec({required this.monthName, required this.day});

  static const _monthMap = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12,
  };

  int get _month => _monthMap[monthName] ?? 1;

  /// The day this falls on in [date]'s year, clamped to the last day of the
  /// month (so `february 30th` resolves to the 28th/29th).
  int _effectiveDay(DateTime date) {
    final last = daysInMonth(date.year, _month);
    return day > last ? last : day;
  }

  @override
  bool isDueOnDay(DateTime date, List<DateTime> completions) {
    if (date.month != _month || date.day != _effectiveDay(date)) return false;
    final dayStart = _startOfDay(date);
    return !completions.any((c) => _startOfDay(c) == dayStart);
  }

  @override
  int requiredOnDay(DateTime date, List<DateTime> completions) =>
    (date.month == _month && date.day == _effectiveDay(date)) ? 1 : 0;

  @override
  int completedOnDay(DateTime date, List<DateTime> completions) {
    final dayStart = _startOfDay(date);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => '${monthName.substring(0, 3)} $day';
}

class YearlyMonthHabitSpec extends HabitSpec {
  final String monthName;

  YearlyMonthHabitSpec({required this.monthName});

  static const _monthMap = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12,
  };

  int get _month => _monthMap[monthName] ?? 1;

  @override
  bool isDueOnDay(DateTime date, List<DateTime> completions) {
    if (date.month != _month) return false;
    // Due if no completion this year in this month
    return !completions.any((c) => c.year == date.year && c.month == _month);
  }

  @override
  int requiredOnDay(DateTime date, List<DateTime> completions) => date.month == _month ? 1 : 0;

  /// The whole month is one window: completing it on any day satisfies it.
  @override
  ({DateTime start, DateTime end})? periodBounds(DateTime date) {
    if (date.month != _month) return null;
    return (
      start: DateTime(date.year, _month, 1),
      end: DateTime(date.year, _month + 1, 1),
    );
  }

  @override
  int completedOnDay(DateTime date, List<DateTime> completions) {
    final dayStart = _startOfDay(date);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => monthName.substring(0, 3);
}

/// Occurrences banked toward the next activation of a dependency habit
/// (`@habit[every 4 @drive]`, `@habit[after 4 a3f7]`).
///
/// Each qualifying occurrence adds one credit; each completion spends
/// [requiredCount] of them, never dropping below zero. Spending rather than
/// resetting means occurrences logged between "due" and "completed" carry over,
/// so the habit comes due *with* the 4th occurrence of every cycle instead of
/// drifting later each time. Completing early costs only what is banked, so it
/// never leaves a debt.
///
/// Occurrences before the habit's first entry don't count, and [asOf] (an
/// exclusive upper bound) limits the tally to events up to a point in time.
int dependencyCredits({
  required List<DateTime> occurrences,
  required List<DateTime> completions,
  required int requiredCount,
  DateTime? asOf,
}) {
  if (requiredCount <= 0) return 0;
  bool inRange(DateTime t) => asOf == null || t.isBefore(asOf);

  final pastCompletions = completions.where(inRange).toList()..sort();
  if (pastCompletions.isEmpty) {
    return occurrences.where(inRange).length;
  }

  // The habit's own defining entry is its first completion; it starts the
  // count rather than spending credits.
  final start = pastCompletions.first;
  final events = <({DateTime at, bool isCompletion})>[
    for (final t in occurrences)
      if (t.isAfter(start) && inRange(t)) (at: t, isCompletion: false),
    for (final c in pastCompletions.skip(1)) (at: c, isCompletion: true),
  ]..sort((a, b) => a.at.compareTo(b.at));

  int credits = 0;
  for (final e in events) {
    if (e.isCompletion) {
      credits -= requiredCount;
      if (credits < 0) credits = 0;
    } else {
      credits++;
    }
  }
  return credits;
}

/// Exclusive end-of-day bound for [day], for use with [dependencyCredits].
DateTime _endOfDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

class DependencyHabitSpec extends HabitSpec {
  final int requiredCount;
  final String dependencyHash;

  /// Timestamps of entries whose content hash matches [dependencyHash].
  /// Set externally before calling [isDueOnDay].
  List<DateTime> hashOccurrences = [];

  DependencyHabitSpec({required this.requiredCount, required this.dependencyHash});

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    if (hashOccurrences.isEmpty) return false;
    return creditsOnDay(day, completions) >= requiredCount;
  }

  /// Occurrences banked toward activation as of the end of [day].
  int creditsOnDay(DateTime day, List<DateTime> completions) => dependencyCredits(
        occurrences: hashOccurrences,
        completions: completions,
        requiredCount: requiredCount,
        asOf: _endOfDay(day),
      );

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => 1;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => 'after $requiredCount $dependencyHash';
}

class DependencyTagHabitSpec extends HabitSpec {
  final int requiredCount;
  final String tag;

  /// Timestamps of entries matching [tag]. Set externally before calling
  /// [isDueOnDay] (e.g. by the habit screen when building the habit list).
  List<DateTime> tagOccurrences = [];

  DependencyTagHabitSpec({required this.requiredCount, required this.tag});

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    if (tagOccurrences.isEmpty) return false;
    return creditsOnDay(day, completions) >= requiredCount;
  }

  /// Tagged entries banked toward activation as of the end of [day].
  int creditsOnDay(DateTime day, List<DateTime> completions) => dependencyCredits(
        occurrences: tagOccurrences,
        completions: completions,
        requiredCount: requiredCount,
        asOf: _endOfDay(day),
      );

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => 1;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => '$requiredCount $tag';
}

/// Combines multiple specs — due if ANY sub-spec says it's due.
class CompositeHabitSpec extends HabitSpec {
  final List<HabitSpec> specs;

  CompositeHabitSpec({required this.specs});

  /// Month-of-year sub-specs act as a scope (when the habit applies) rather
  /// than as an alternative rule, so `[november, 1d]` means "daily, but only
  /// during November" instead of "daily, or once in November".
  List<YearlyMonthHabitSpec> get _scopes =>
      specs.whereType<YearlyMonthHabitSpec>().toList();

  List<HabitSpec> get _rules =>
      specs.where((s) => s is! YearlyMonthHabitSpec).toList();

  bool _inScope(DateTime day) {
    final scopes = _scopes;
    if (scopes.isEmpty) return true;
    return scopes.any((s) => s.requiredOnDay(day, const []) > 0);
  }

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) {
    if (!_inScope(day)) return false;
    // Due if any applicable sub-spec is due AND not already completed today
    final dayStart = _startOfDay(day);
    final completedToday = completions.where((c) => _startOfDay(c) == dayStart).length;
    if (completedToday > 0) return false;
    final rules = _rules.isEmpty ? specs : _rules;
    return rules.any((s) => s.isDueOnDay(day, completions));
  }

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) {
    if (!_inScope(day)) return 0;
    final rules = _rules.isEmpty ? specs : _rules;
    return rules.any((s) => s.requiredOnDay(day, completions) > 0) ? 1 : 0;
  }

  @override
  ({DateTime start, DateTime end})? periodBounds(DateTime day) {
    if (!_inScope(day)) return null;
    final rules = _rules.isEmpty ? specs : _rules;
    for (final s in rules) {
      final bounds = s.periodBounds(day);
      if (bounds != null) return bounds;
    }
    return null;
  }

  @override
  int requiredInPeriod(DateTime day) {
    final rules = _rules.isEmpty ? specs : _rules;
    for (final s in rules) {
      if (s.periodBounds(day) != null) return s.requiredInPeriod(day);
    }
    return 1;
  }

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => specs.map((s) => s.displayLabel).join(', ');
}

class DiscontinuedHabitSpec extends HabitSpec {
  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) => false;

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => 0;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) => 0;

  @override
  String get displayLabel => 'ended';
}

class NegativeHabitSpec extends HabitSpec {
  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) => false;

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => 0;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return completions.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => 'avoid';
}

class NegativeTagHabitSpec extends HabitSpec {
  final String tag;

  /// Timestamps of entries matching [tag]. Set externally before calling
  /// strength calculations (e.g. by the habit screen when building the habit list).
  List<DateTime> tagOccurrences = [];

  NegativeTagHabitSpec({required this.tag});

  @override
  bool isDueOnDay(DateTime day, List<DateTime> completions) => false;

  @override
  int requiredOnDay(DateTime day, List<DateTime> completions) => 0;

  @override
  int completedOnDay(DateTime day, List<DateTime> completions) {
    final dayStart = _startOfDay(day);
    return tagOccurrences.where((c) => _startOfDay(c) == dayStart).length;
  }

  @override
  String get displayLabel => 'avoid $tag';
}

/// Regex matching #when[YYYY-MM-DD H:MM:SS AM/PM]
final RegExp whenTagRegex = RegExp(r'#when\[\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}:\d{2}\s+[AP]M\]');

/// Parse the datetime value inside a #when[...] tag.
DateTime? parseWhenDateTime(String tag) {
  final match = RegExp(r'#when\[(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(AM|PM)\]').firstMatch(tag);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  var hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final period = match.group(7)!;
  if (period == 'AM' && hour == 12) hour = 0;
  if (period == 'PM' && hour != 12) hour += 12;
  return DateTime(year, month, day, hour, minute, second);
}

/// Format a DateTime as a #when[...] tag string.
String formatWhenTag(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  var hour = dt.hour;
  final period = hour >= 12 ? 'PM' : 'AM';
  if (hour == 0) {
    hour = 12;
  } else if (hour > 12) {
    hour -= 12;
  }
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  return '#when[$y-$m-$d $hour:$min:$sec $period]';
}

/// Extract all #when dates from entry text.
List<DateTime> extractWhenDates(String text) {
  final dates = <DateTime>[];
  for (final match in whenTagRegex.allMatches(text)) {
    final dt = parseWhenDateTime(match.group(0)!);
    if (dt != null) dates.add(dt);
  }
  return dates;
}

// Default time windows in minutes
const int defaultAroundNowWindow = 60;
const int defaultRelatedEntriesWindow = 30;
const int defaultGroupingWindow = 5;

Future<File> _getSettingsFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan_settings.txt');
}

Future<Map<String, int>> loadTimeSettings() async {
  try {
    final file = await _getSettingsFile();
    if (await file.exists()) {
      final contents = await file.readAsString();
      final lines = contents.split('\n');
      final settings = <String, int>{};
      for (final line in lines) {
        if (line.contains('=')) {
          final parts = line.split('=');
          settings[parts[0]] = int.tryParse(parts[1]) ?? 0;
        }
      }
      return {
        'aroundNow': settings['aroundNow'] ?? defaultAroundNowWindow,
        'relatedEntries': settings['relatedEntries'] ?? defaultRelatedEntriesWindow,
        'groupingWindow': settings['groupingWindow'] ?? defaultGroupingWindow,
      };
    }
  } catch (e) {
    // Silently fail
  }
  return {
    'aroundNow': defaultAroundNowWindow,
    'relatedEntries': defaultRelatedEntriesWindow,
    'groupingWindow': defaultGroupingWindow,
  };
}

Future<void> saveTimeSettings(int aroundNow, int relatedEntries, [int? groupingWindow]) async {
  try {
    final file = await _getSettingsFile();
    final gw = groupingWindow ?? defaultGroupingWindow;
    await file.writeAsString('aroundNow=$aroundNow\nrelatedEntries=$relatedEntries\ngroupingWindow=$gw');
  } catch (e) {
    // Silently fail
  }
}

Future<bool> loadBoolSetting(String key, {bool defaultValue = false}) async {
  try {
    final file = await _getSettingsFile();
    if (await file.exists()) {
      final contents = await file.readAsString();
      for (final line in contents.split('\n')) {
        if (line.startsWith('$key=')) {
          return line.substring(key.length + 1) == 'true';
        }
      }
    }
  } catch (e) {
    // Silently fail
  }
  return defaultValue;
}

Future<void> saveBoolSetting(String key, bool value) async {
  try {
    final file = await _getSettingsFile();
    var contents = '';
    if (await file.exists()) {
      contents = await file.readAsString();
      final lines = contents.split('\n').where((l) => !l.startsWith('$key=')).toList();
      contents = lines.join('\n');
    }
    if (contents.isNotEmpty && !contents.endsWith('\n')) contents += '\n';
    contents += '$key=$value';
    await file.writeAsString(contents);
  } catch (e) {
    // Silently fail
  }
}

Future<String> loadStringSetting(String key, {String defaultValue = ''}) async {
  try {
    final file = await _getSettingsFile();
    if (await file.exists()) {
      final contents = await file.readAsString();
      for (final line in contents.split('\n')) {
        if (line.startsWith('$key=')) {
          return line.substring(key.length + 1);
        }
      }
    }
  } catch (e) {
    // Silently fail
  }
  return defaultValue;
}

Future<void> saveStringSetting(String key, String value) async {
  try {
    final file = await _getSettingsFile();
    var contents = '';
    if (await file.exists()) {
      contents = await file.readAsString();
      final lines = contents.split('\n').where((l) => !l.startsWith('$key=')).toList();
      contents = lines.join('\n');
    }
    if (contents.isNotEmpty && !contents.endsWith('\n')) contents += '\n';
    contents += '$key=$value';
    await file.writeAsString(contents);
  } catch (e) {
    // Silently fail
  }
}

Future<File> getFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan.csv');
}

Future<Directory> getBackupDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  final backupDir = Directory('${directory.path}/bunyan_backups');
  if (!await backupDir.exists()) {
    await backupDir.create(recursive: true);
  }
  return backupDir;
}

Future<File> getLastBackupDateFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan_last_backup.txt');
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

Future<bool> shouldBackupToday() async {
  final lastBackupFile = await getLastBackupDateFile();
  if (!await lastBackupFile.exists()) {
    return true;
  }
  final lastBackupDate = await lastBackupFile.readAsString();
  final today = _formatDate(DateTime.now());
  return lastBackupDate.trim() != today;
}

Future<void> createBackup() async {
  final sourceFile = await getFile();
  if (!await sourceFile.exists()) {
    return; // Nothing to backup
  }

  final backupDir = await getBackupDirectory();
  final today = _formatDate(DateTime.now());
  final backupFile = File('${backupDir.path}/bunyan_backup_$today.csv');

  await sourceFile.copy(backupFile.path);

  // Update last backup date
  final lastBackupFile = await getLastBackupDateFile();
  await lastBackupFile.writeAsString(today);

  // Rotate old backups
  await rotateBackups();
}

Future<void> rotateBackups() async {
  final backupDir = await getBackupDirectory();
  final files = await backupDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.csv'))
      .cast<File>()
      .toList();

  // Sort by name (which includes date) descending - newest first
  files.sort((a, b) => b.path.compareTo(a.path));

  // Delete old backups beyond the limit
  if (files.length > maxBackups) {
    for (var i = maxBackups; i < files.length; i++) {
      await files[i].delete();
    }
  }
}

Future<List<FileSystemEntity>> getBackups() async {
  final backupDir = await getBackupDirectory();
  if (!await backupDir.exists()) {
    return [];
  }

  final files = await backupDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.csv'))
      .toList();

  // Sort by name descending - newest first
  files.sort((a, b) => b.path.compareTo(a.path));
  return files;
}

Future<void> restoreBackup(File backupFile) async {
  final targetFile = await getFile();
  await backupFile.copy(targetFile.path);
}

Future<void> deleteBackup(File backupFile) async {
  if (await backupFile.exists()) {
    await backupFile.delete();
  }
}

String getBackupDisplayName(String path) {
  // Extract date from filename like "bunyan_backup_2024-01-15.csv"
  final filename = path.split('/').last.split('\\').last;
  final match = RegExp(r'bunyan_backup_(\d{4}-\d{2}-\d{2})\.csv').firstMatch(filename);
  if (match != null) {
    return match.group(1)!;
  }
  return filename;
}

Future<int> getBackupEntryCount(File backupFile) async {
  if (!await backupFile.exists()) return 0;
  final contents = await backupFile.readAsString();
  return contents.split('\n').where((line) => line.isNotEmpty).length;
}

const _backupChannel = MethodChannel('com.example.bunyan/backup');

/// Request Android to back up app data to Google cloud.
/// This notifies the OS that data has changed and should be backed up soon.
/// Emoji-stripping regex: matches most Unicode emoji ranges.
final _emojiRegex = RegExp(
  r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|'
  r'[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|'
  r'[\u{FE00}-\u{FE0F}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|'
  r'[\u{1FA70}-\u{1FAFF}]|[\u{200D}]|[\u{20E3}]|[\u{E0020}-\u{E007F}]',
  unicode: true,
);

/// Tokenized search: strips emojis, splits query into words, and checks that
/// every query word appears somewhere in the entry text.
/// Preserves tag characters (@, #, etc.) so tag searches still work.
bool matchesSearch(String entryText, String query) {
  final normEntry = entryText.replaceAll(_emojiRegex, ' ').toLowerCase();
  final normQuery = query.replaceAll(_emojiRegex, ' ').toLowerCase();
  final queryWords = normQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return queryWords.every((word) => normEntry.contains(word));
}

Future<bool> requestGoogleBackup() async {
  try {
    if (!Platform.isAndroid) return false;
    final result = await _backupChannel.invokeMethod('requestBackup');
    return result == true;
  } catch (e) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Todo / pin helpers
// ---------------------------------------------------------------------------

/// Generate the 8-char hash used to link a `#done` entry to its `#todo`.
String generateTodoHash(String text, DateTime timestamp) {
  final combined = '$text${timestamp.toIso8601String()}';
  final bytes = utf8.encode(combined);
  int hash = 0;
  for (final byte in bytes) {
    hash = ((hash << 5) - hash) + byte;
    hash = hash & 0x7FFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
}

/// True when the entry text carries a `#todo` tag.
bool isTodoText(String text) => text.toLowerCase().contains('#todo');

/// True when the entry text is a `#done` completion record.
bool isDoneText(String text) => text.toLowerCase().contains('#done');

/// True when the entry text is pinned with `#pin`.
bool isPinnedText(String text) => text.toLowerCase().contains('#pin');

/// Build the `#done <hash> <text>` record that completes a todo.
String buildDoneText(String todoText, DateTime todoTimestamp) {
  final hash = generateTodoHash(todoText, todoTimestamp);
  final cleaned =
      todoText.replaceAll(RegExp(r'#todo', caseSensitive: false), '').trim();
  return '#done $hash $cleaned';
}

/// Strip tags (leading-char words) from text for display purposes.
String stripTags(String text) {
  final words = text
      .split(' ')
      .where((w) => w.isEmpty || !tagLeaders.contains(w[0]))
      .toList();
  return words.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
