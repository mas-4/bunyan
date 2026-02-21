import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/habit_logic.dart';
import 'package:bunyan/utils.dart';

void main() {
  group('calculateHabitStrength', () {
    test('empty completions returns 0.0', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      expect(calculateHabitStrength(spec, [], today: DateTime(2025, 3, 10)), 0.0);
    });

    test('every day completed on a 1d interval habit returns 1.0', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      final today = DateTime(2025, 3, 10);
      // Complete every day from March 1–10
      final completions = List.generate(
        10,
        (i) => DateTime(2025, 3, 1 + i, 9, 0),
      );
      expect(calculateHabitStrength(spec, completions, today: today), 1.0);
    });

    test('half the days missed on a 1/d frequency habit returns 0.5', () {
      // Use FrequencyHabitSpec so each day is independently tracked
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'd');
      final today = DateTime(2025, 3, 10);
      // Complete only odd days: March 1, 3, 5, 7, 9 (5 out of 10)
      final completions = [
        DateTime(2025, 3, 1, 9, 0),
        DateTime(2025, 3, 3, 9, 0),
        DateTime(2025, 3, 5, 9, 0),
        DateTime(2025, 3, 7, 9, 0),
        DateTime(2025, 3, 9, 9, 0),
      ];
      final strength = calculateHabitStrength(spec, completions, today: today);
      expect(strength, closeTo(0.5, 0.1));
    });

    test('with periodDays window clamps to window', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      final today = DateTime(2025, 3, 10);
      // Complete every day March 1–10 but only look at last 7 days
      final completions = List.generate(
        10,
        (i) => DateTime(2025, 3, 1 + i, 9, 0),
      );
      final strength = calculateHabitStrength(
        spec, completions,
        periodDays: 7,
        today: today,
      );
      expect(strength, 1.0);
    });

    test('periodDays window shows lower strength when days missed', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      final today = DateTime(2025, 3, 10);
      // Complete only March 1–5, then miss March 6–10
      final completions = List.generate(
        5,
        (i) => DateTime(2025, 3, 1 + i, 9, 0),
      );
      // Last 7 days: March 4–10, completed only 4,5 → 2/7
      final strength = calculateHabitStrength(
        spec, completions,
        periodDays: 7,
        today: today,
      );
      expect(strength, lessThan(0.5));
    });

    test('weekly weekday habit with mixed completions', () {
      // Due every Monday
      final spec = WeekdayHabitSpec(dayName: 'monday');
      // Check on a Wednesday so we evaluate past Mondays cleanly
      // Mondays in March 2025: 3, 10, 17, 24
      final today = DateTime(2025, 3, 26); // Wednesday after 4 Mondays
      // Complete 2 out of 4 Mondays
      final completions = [
        DateTime(2025, 3, 3, 9, 0),
        DateTime(2025, 3, 17, 9, 0),
      ];
      final strength = calculateHabitStrength(spec, completions, today: today);
      // 2 satisfied out of 4 Mondays → 0.5
      expect(strength, closeTo(0.5, 0.05));
    });
  });

  group('nextDueDayIndex', () {
    test('habit due today returns 0', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      // No completions → always due
      expect(nextDueDayIndex(spec, [], today: DateTime(2025, 3, 10)), 0);
    });

    test('habit just completed with interval 2d returns 1 or 2', () {
      final spec = IntervalHabitSpec(interval: 2, unit: 'd');
      final today = DateTime(2025, 3, 10);
      final completions = [DateTime(2025, 3, 10, 9, 0)];
      final result = nextDueDayIndex(spec, completions, today: today);
      // Completed today, interval is 2d, so next due in 2 days
      expect(result, 2);
    });

    test('not due within 366 days returns 999', () {
      // A yearly spec that was just completed
      final spec = IntervalHabitSpec(interval: 2, unit: 'y');
      final today = DateTime(2025, 3, 10);
      final completions = [DateTime(2025, 3, 10, 9, 0)];
      final result = nextDueDayIndex(spec, completions, today: today);
      expect(result, 999);
    });

    test('weekday habit returns days until that weekday', () {
      // Due on Fridays. March 10, 2025 is a Monday.
      final spec = WeekdayHabitSpec(dayName: 'friday');
      final today = DateTime(2025, 3, 10);
      final result = nextDueDayIndex(spec, [], today: today);
      // Monday to Friday = 4 days
      expect(result, 4);
    });
  });

  group('extractFirstTag', () {
    test('string with #tag returns the tag', () {
      expect(extractFirstTag('#health retinol'), '#health');
    });

    test('string without tag returns null', () {
      expect(extractFirstTag('retinol'), null);
    });

    test('multiple tags returns the first one', () {
      expect(extractFirstTag('#a #b stuff'), '#a');
    });

    test('tag in the middle of string', () {
      expect(extractFirstTag('take #vitamins daily'), '#vitamins');
    });

    test('empty string returns null', () {
      expect(extractFirstTag(''), null);
    });
  });
}
