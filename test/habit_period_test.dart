import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/habit_logic.dart';
import 'package:bunyan/utils.dart';

/// Regression tests for specs whose obligation spans a window longer than a
/// day (`3/w`, `1/m`, `november`). These used to be scored once per *day* of
/// the window, so a perfectly kept `1/m` habit reported ~7% strength and never
/// built a streak.
void main() {
  group('frequency habit strength is scored per window', () {
    test('1/w done every week returns 1.0', () {
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'w');
      final completions = [
        DateTime(2025, 11, 5, 9), // week of Nov 3
        DateTime(2025, 11, 12, 9), // week of Nov 10
        DateTime(2025, 11, 19, 9), // week of Nov 17
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 21)),
        1.0,
      );
    });

    test('1/w with one week skipped returns 2/3', () {
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'w');
      final completions = [
        DateTime(2025, 11, 5, 9), // week of Nov 3
        // week of Nov 10 skipped
        DateTime(2025, 11, 19, 9), // week of Nov 17 (still open on Nov 21)
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 21)),
        closeTo(2 / 3, 0.001),
      );
    });

    test('3/w met every week returns 1.0', () {
      final spec = FrequencyHabitSpec(count: 3, periodUnit: 'w');
      final completions = [
        DateTime(2025, 11, 3), DateTime(2025, 11, 5), DateTime(2025, 11, 7),
        DateTime(2025, 11, 10), DateTime(2025, 11, 12), DateTime(2025, 11, 14),
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 16)),
        1.0,
      );
    });

    test('3/w short by one in a closed week counts that week as missed', () {
      final spec = FrequencyHabitSpec(count: 3, periodUnit: 'w');
      final completions = [
        DateTime(2025, 11, 3), DateTime(2025, 11, 5), // only 2 in week of Nov 3
        DateTime(2025, 11, 10), DateTime(2025, 11, 12), DateTime(2025, 11, 14),
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 16)),
        closeTo(0.5, 0.001),
      );
    });

    test('1/m done monthly returns 1.0 and streaks per month', () {
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'm');
      final completions = [
        DateTime(2025, 9, 20),
        DateTime(2025, 10, 20),
        DateTime(2025, 11, 20),
      ];
      final today = DateTime(2025, 11, 30);
      expect(calculateHabitStrength(spec, completions, today: today), 1.0);
      expect(calculateCurrentStreak(spec, completions, today: today), 3);
    });

    test('an open window is not counted as missed yet', () {
      final spec = FrequencyHabitSpec(count: 3, periodUnit: 'w');
      // Week of Nov 17 is still open on Nov 18 with only one completion.
      final completions = [
        DateTime(2025, 11, 10), DateTime(2025, 11, 12), DateTime(2025, 11, 14),
        DateTime(2025, 11, 17),
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 18)),
        1.0,
      );
    });

    test('a missed closed week still breaks the streak', () {
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'w');
      final completions = [
        DateTime(2025, 11, 5), // week of Nov 3
        // week of Nov 10 skipped
        DateTime(2025, 11, 19), // week of Nov 17
      ];
      expect(
        calculateCurrentStreak(spec, completions, today: DateTime(2025, 11, 21)),
        1,
      );
    });
  });

  group('month-of-year habits', () {
    final spec = YearlyMonthHabitSpec(monthName: 'november');

    test('done once in november returns 1.0', () {
      final completions = [DateTime(2025, 11, 10, 9)];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 30)),
        1.0,
      );
      expect(
        calculateCurrentStreak(spec, completions, today: DateTime(2025, 11, 30)),
        1,
      );
    });

    test('earlier days of the month are not misses once november is done', () {
      // The habit-defining entry in February also counts as a completion.
      final completions = [DateTime(2025, 2, 3, 12), DateTime(2025, 11, 10, 9)];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 30)),
        1.0,
      );
    });

    test('november still open is not penalized', () {
      final completions = [DateTime(2025, 2, 3, 12)];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 9)),
        1.0,
      );
    });

    test('a november that came and went unfinished counts as missed', () {
      final completions = [DateTime(2024, 6, 1), DateTime(2025, 11, 10)];
      // 2024 november missed, 2025 november done.
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 30)),
        closeTo(0.5, 0.001),
      );
    });

    test('is not due outside november', () {
      expect(spec.isDueOnDay(DateTime(2025, 6, 15), []), isFalse);
      expect(spec.periodBounds(DateTime(2025, 6, 15)), isNull);
      expect(spec.periodBounds(DateTime(2025, 11, 15)), isNotNull);
    });
  });

  group('composite specs', () {
    test('month + interval scopes the interval to that month', () {
      final spec = parseHabitSpec('pushups @habit[november, 1d]')!;
      expect(spec, isA<CompositeHabitSpec>());
      expect(spec.isDueOnDay(DateTime(2025, 6, 15), []), isFalse,
          reason: 'a november-scoped daily habit is not due in June');
      expect(spec.requiredOnDay(DateTime(2025, 6, 15), []), 0);
      expect(spec.isDueOnDay(DateTime(2025, 11, 15), []), isTrue);
      expect(spec.requiredOnDay(DateTime(2025, 11, 15), []), 1);
    });

    test('two weekdays still mean either day', () {
      final spec = parseHabitSpec('gym @habit[monday, thursday]')!;
      expect(spec.isDueOnDay(DateTime(2025, 11, 3), []), isTrue); // Monday
      expect(spec.isDueOnDay(DateTime(2025, 11, 6), []), isTrue); // Thursday
      expect(spec.isDueOnDay(DateTime(2025, 11, 4), []), isFalse); // Tuesday
    });

    test('two months still mean either month', () {
      final spec = parseHabitSpec('gutters @habit[november, december]')!;
      expect(spec.isDueOnDay(DateTime(2025, 11, 15), []), isTrue);
      expect(spec.isDueOnDay(DateTime(2025, 12, 15), []), isTrue);
      expect(spec.isDueOnDay(DateTime(2025, 10, 15), []), isFalse);
    });
  });

  group('date-of-month habits clamp to short months', () {
    test('the 31st falls on the last day of february', () {
      final spec = MonthlyDateHabitSpec(day: 31);
      expect(spec.isDueOnDay(DateTime(2025, 2, 28), []), isTrue);
      expect(spec.isDueOnDay(DateTime(2025, 2, 27), []), isFalse);
      expect(spec.isDueOnDay(DateTime(2024, 2, 29), []), isTrue); // leap year
      expect(spec.isDueOnDay(DateTime(2025, 3, 31), []), isTrue);
      expect(spec.isDueOnDay(DateTime(2025, 4, 30), []), isTrue);
    });

    test('a yearly date beyond the month length clamps too', () {
      final spec = YearlyDateHabitSpec(monthName: 'february', day: 30);
      expect(spec.isDueOnDay(DateTime(2025, 2, 28), []), isTrue);
      expect(spec.isDueOnDay(DateTime(2024, 2, 29), []), isTrue);
    });

    test('daysInMonth covers leap years', () {
      expect(daysInMonth(2025, 2), 28);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2025, 4), 30);
      expect(daysInMonth(2025, 12), 31);
    });
  });

  group('per-day specs are unchanged', () {
    test('1d interval with a missed day', () {
      final spec = IntervalHabitSpec(interval: 1, unit: 'd');
      final completions = [
        DateTime(2025, 11, 1),
        DateTime(2025, 11, 2),
        // Nov 3 missed
        DateTime(2025, 11, 4),
      ];
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 4)),
        closeTo(0.75, 0.001),
      );
    });

    test('1/d frequency is still scored day by day', () {
      final spec = FrequencyHabitSpec(count: 1, periodUnit: 'd');
      final completions = [
        DateTime(2025, 11, 1),
        DateTime(2025, 11, 3),
      ];
      expect(spec.periodBounds(DateTime(2025, 11, 1)), isNull);
      expect(
        calculateHabitStrength(spec, completions, today: DateTime(2025, 11, 4)),
        closeTo(0.5, 0.001),
      );
    });
  });

  group('negative spec syntax', () {
    test('the documented "not" forms parse', () {
      expect(parseHabitSpec('soda @habit[not 1d]'), isA<NegativeHabitSpec>());
      expect(parseHabitSpec('soda @habit[not]'), isA<NegativeHabitSpec>());
      expect(parseHabitSpec('smoke @habit[not 3 @smoke]'),
          isA<NegativeTagHabitSpec>());
      expect(parseHabitSpec('smoke @habit[not @smoke]'),
          isA<NegativeTagHabitSpec>());
      expect(
        (parseHabitSpec('smoke @habit[not 3 @smoke]') as NegativeTagHabitSpec)
            .tag,
        '@smoke',
      );
    });

    test('the short forms still parse', () {
      expect(parseHabitSpec('soda @habit[-]'), isA<NegativeHabitSpec>());
      expect(parseHabitSpec('soda @habit[neg]'), isA<NegativeHabitSpec>());
      expect(parseHabitSpec('soda @habit[negative]'), isA<NegativeHabitSpec>());
      expect(parseHabitSpec('smoke @habit[-@smoke]'),
          isA<NegativeTagHabitSpec>());
    });
  });
}
