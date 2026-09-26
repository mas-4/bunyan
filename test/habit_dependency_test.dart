import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/utils.dart';

/// Regression tests for dependency ("queued") habits — `@habit[every 4 @drive]`
/// and `@habit[after 4 a3f7]`.
///
/// These used to reset the counter to zero on completion, so occurrences logged
/// between "came due" and "actually completed" were thrown away and each cycle
/// drifted later: due at drive 4, then not again until drive 10.
void main() {
  // The habit's defining entry is its own first completion.
  final definedAt = DateTime(2025, 1, 1, 8);
  DateTime drive(int day) => DateTime(2025, 1, day, 10);

  group('tag dependency', () {
    DependencyTagHabitSpec specWith(List<DateTime> occurrences) {
      return DependencyTagHabitSpec(requiredCount: 4, tag: '@drive')
        ..tagOccurrences = occurrences;
    }

    test('comes due with the 4th occurrence, not after it', () {
      for (var n = 1; n <= 5; n++) {
        final spec = specWith([for (var d = 2; d <= n + 1; d++) drive(d)]);
        expect(
          spec.isDueOnDay(drive(n + 1), [definedAt]),
          n >= 4,
          reason: 'with $n occurrences logged',
        );
      }
    });

    test('surplus occurrences carry over to the next cycle', () {
      // Due at drive 4 (Jan 5), two more drives logged, completed Jan 8.
      final occurrences = [for (var d = 2; d <= 7; d++) drive(d)]; // 6 drives
      final completions = [definedAt, DateTime(2025, 1, 8, 9)];

      expect(specWith(occurrences).isDueOnDay(DateTime(2025, 1, 8, 20), completions),
          isFalse, reason: 'just completed');

      // The next activation lands on the 8th drive overall (4 after the 4th),
      // not the 10th — the two surplus drives are not discarded.
      final withSeventh = [...occurrences, drive(9)];
      expect(specWith(withSeventh).isDueOnDay(drive(9), completions), isFalse);

      final withEighth = [...withSeventh, drive(10)];
      expect(specWith(withEighth).isDueOnDay(drive(10), completions), isTrue);
    });

    test('completing early does not leave a debt', () {
      // Completed after only two drives; the next cycle still needs 4, counted
      // from zero rather than from -2.
      final completions = [definedAt, DateTime(2025, 1, 4, 9)];
      final twoThenFour = [
        drive(2), drive(3), // spent (only 2 banked) by the Jan 4 completion
        drive(5), drive(6), drive(7), drive(8),
      ];
      expect(specWith(twoThenFour).isDueOnDay(drive(8), completions), isTrue);
    });

    test('occurrences before the habit existed do not count', () {
      final before = [DateTime(2024, 12, 20), DateTime(2024, 12, 21),
                      DateTime(2024, 12, 22), DateTime(2024, 12, 23)];
      expect(specWith(before).isDueOnDay(drive(2), [definedAt]), isFalse);
    });

    test('credits are counted as of the given day', () {
      final spec = specWith([drive(2), drive(3), drive(4), drive(5)]);
      // On Jan 3 only two drives had happened.
      expect(spec.creditsOnDay(drive(3), [definedAt]), 2);
      expect(spec.isDueOnDay(drive(3), [definedAt]), isFalse);
      expect(spec.creditsOnDay(drive(5), [definedAt]), 4);
      expect(spec.isDueOnDay(drive(5), [definedAt]), isTrue);
    });
  });

  group('hash dependency', () {
    test('comes due with the 4th occurrence and carries surplus', () {
      DependencyHabitSpec specWith(List<DateTime> occurrences) =>
          DependencyHabitSpec(requiredCount: 4, dependencyHash: 'a3f7')
            ..hashOccurrences = occurrences;

      expect(
        specWith([drive(2), drive(3), drive(4)]).isDueOnDay(drive(4), [definedAt]),
        isFalse,
      );
      expect(
        specWith([drive(2), drive(3), drive(4), drive(5)])
            .isDueOnDay(drive(5), [definedAt]),
        isTrue,
      );

      // Six occurrences, completed on Jan 8 → two carry over, so two more
      // bring it back rather than four.
      final completions = [definedAt, DateTime(2025, 1, 8, 9)];
      final occurrences = [for (var d = 2; d <= 7; d++) drive(d)];
      expect(
        specWith([...occurrences, drive(9)]).isDueOnDay(drive(9), completions),
        isFalse,
      );
      expect(
        specWith([...occurrences, drive(9), drive(10)])
            .isDueOnDay(drive(10), completions),
        isTrue,
      );
    });
  });

  group('dependencyCredits', () {
    test('no completions means every occurrence counts', () {
      expect(
        dependencyCredits(
          occurrences: [drive(2), drive(3)],
          completions: const [],
          requiredCount: 4,
        ),
        2,
      );
    });

    test('a completion spends exactly the required count', () {
      final credits = dependencyCredits(
        occurrences: [for (var d = 2; d <= 8; d++) drive(d)], // 7
        completions: [definedAt, DateTime(2025, 1, 9)],
        requiredCount: 4,
      );
      expect(credits, 3);
    });

    test('requiredCount of zero yields no credits', () {
      expect(
        dependencyCredits(
          occurrences: [drive(2)],
          completions: [definedAt],
          requiredCount: 0,
        ),
        0,
      );
    });
  });
}
