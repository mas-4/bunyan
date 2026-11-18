import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/day_stats.dart';
import 'package:bunyan/models.dart';
import 'package:bunyan/utils.dart';

WordEntry e(String word, DateTime at) => WordEntry(word: word, timestamp: at);

void main() {
  final day = DateTime(2026, 11, 18);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 18, h, m);

  group('computeDayStats', () {
    test('empty day', () {
      final s = computeDayStats([e('coffee', DateTime(2026, 11, 17, 8))], day);
      expect(s.isEmpty, isTrue);
      expect(s.first, isNull);
      expect(s.busiestHour, isNull);
      expect(s.activeSpan, isNull);
    });

    test('counts, categories, and span', () {
      final todo = e('buy milk #todo', DateTime(2026, 11, 16, 12));
      final entries = [
        e('coffee #drink', at(8, 5)),
        e('coffee #drink', at(9, 15)),
        e('run @habit[1d]', at(9, 40)),
        e('idea #note #work', at(14)),
        e('call mom #todo', at(15)),
        e(buildDoneText(todo.word, todo.timestamp), at(17, 30)),
        e('next day', DateTime(2026, 11, 19, 1)),
        todo,
      ];
      final s = computeDayStats(entries, day);

      expect(s.timeline.length, 6);
      expect(s.entries.length, 5);
      expect(s.uniqueCount, 4);
      expect(s.completedTodos, 1);
      expect(s.newTodos, 1);
      expect(s.habitLogs, 1);
      expect(s.notes, 1);
      expect(s.first, at(8, 5));
      expect(s.last, at(17, 30));
      expect(s.activeSpan, const Duration(hours: 9, minutes: 25));
      expect(s.hourly[9], 2);
      expect(s.busiestHour, 9);
      expect(s.longestGap, const Duration(hours: 4, minutes: 20));
      expect(s.repeated.single.key, 'coffee #drink');
      expect(s.repeated.single.value, 2);
    });

    test('tags exclude system tags and rank by use', () {
      final s = computeDayStats([
        e('a #work #note', at(9)),
        e('b #work @dana #todo', at(10)),
        e('c @dana #work', at(11)),
      ], day);
      expect(s.tags.map((t) => '${t.key}:${t.value}'), ['#work:3', '@dana:2']);
    });

    test('recent average uses the window before the day, clipped to history', () {
      final entries = [
        e('x', DateTime(2026, 11, 14, 9)), // first ever entry, 4 days before
        e('x', DateTime(2026, 11, 15, 9)),
        e('x', DateTime(2026, 11, 15, 10)),
        e('x', DateTime(2026, 11, 17, 9)),
        e('#done 12345678 old', DateTime(2026, 11, 17, 10)), // not counted
        e('x', at(9)), // the day itself isn't part of its own baseline
      ];
      final s = computeDayStats(entries, day);
      expect(s.recentAverage, closeTo(4 / 4, 1e-9));
    });

    test('no baseline on the first day of logging', () {
      final s = computeDayStats([e('x', at(9))], day);
      expect(s.recentAverage, isNull);
    });

    test('scheduled items on the day, with completion state', () {
      final dentist = e('dentist #todo #when[2026-11-18 2:30:00 PM]', DateTime(2026, 11, 1));
      final party = e('party #when[2026-11-18 8:00:00 PM]', DateTime(2026, 11, 2));
      final other = e('later #todo #when[2026-11-25 9:00:00 AM]', DateTime(2026, 11, 3));
      final s = computeDayStats([
        party,
        dentist,
        other,
        e(buildDoneText(dentist.word, dentist.timestamp), DateTime(2026, 11, 18, 15)),
      ], day);

      expect(s.scheduled.length, 2);
      expect(s.scheduled[0].entry, dentist);
      expect(s.scheduled[0].done, isTrue);
      expect(s.scheduled[1].entry, party);
      expect(s.scheduled[1].done, isFalse);
    });
  });

  test('dailyEntryCounts buckets by calendar day and skips #done', () {
    final counts = dailyEntryCounts([
      e('a', DateTime(2026, 11, 16, 23, 59)),
      e('b', DateTime(2026, 11, 17, 0, 1)),
      e('c', DateTime(2026, 11, 17, 12)),
      e('#done 12345678 c', DateTime(2026, 11, 17, 13)),
      e('d', DateTime(2026, 11, 20)),
    ], DateTime(2026, 11, 16), 3);
    expect(counts, [1, 2, 0]);
  });

  test('formatSpan', () {
    expect(formatSpan(const Duration(seconds: 20)), '<1m');
    expect(formatSpan(const Duration(minutes: 45)), '45m');
    expect(formatSpan(const Duration(hours: 2)), '2h');
    expect(formatSpan(const Duration(hours: 3, minutes: 20)), '3h 20m');
  });
}
