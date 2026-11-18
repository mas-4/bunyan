import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/frequency_cache.dart';
import 'package:bunyan/models.dart';
import 'package:bunyan/screens/day_overview_screen.dart';
import 'package:bunyan/screens/notes_screen.dart';
import 'package:bunyan/utils.dart';

void main() {
  final now = DateTime.now();
  DateTime today(int h, [int m = 0]) => DateTime(now.year, now.month, now.day, h, m);

  List<WordEntry> sample() => [
        WordEntry(word: 'coffee #drink', timestamp: today(8)),
        WordEntry(word: 'coffee #drink', timestamp: today(9, 30)),
        WordEntry(word: 'run @habit[1d]', timestamp: today(7)),
        WordEntry(word: buildNoteText('Plan\nwrite the doc', ['#work']), timestamp: today(10)),
        WordEntry(word: buildNoteText('groceries', ['#home']), timestamp: today(11)),
        WordEntry(word: 'call mom #todo', timestamp: today(12)),
      ];

  testWidgets('day overview renders and navigates days', (tester) async {
    final entries = sample();
    await tester.pumpWidget(MaterialApp(
      home: DayOverviewScreen(getEntries: () => entries, initialDay: now),
    ));

    expect(find.text('Today'), findsOneWidget); // relative label
    expect(find.text('ENTRIES'), findsNothing);
    expect(find.text('Entries'), findsOneWidget);
    expect(find.text('BY HOUR'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Plan\nwrite the doc'), 200);
    expect(find.text('TIMELINE · 6'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Today'), -200);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Nothing logged on this day.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes tab filters by tag and the editor saves with quick tags',
      (tester) async {
    final entries = sample();
    final cache = EntryFrequencyCache()..buildFromEntries(entries);
    final added = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: NotesScreen(
        entries: entries,
        cache: cache,
        hotbarTags: const ['#drink', '#when'],
        onAddEntry: (w) async => added.add(w),
        onUpdateEntry: (a, b) async {},
        onDeleteEntry: (e) async {},
      ),
    ));

    expect(find.text('Notes (2)'), findsOneWidget);
    expect(find.text('New note'), findsNothing); // composer replaces the button
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('groceries'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '#when'), findsNothing); // system tag

    // Picking #work both tags the draft and filters the list.
    await tester.tap(find.widgetWithText(FilterChip, '#work'));
    await tester.pump();
    expect(find.text('groceries'), findsNothing);
    expect(find.text('Notes tagged #work · 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '#drink'));
    await tester.enterText(find.byType(TextField), 'line one\nline two');
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(added, hasLength(1));
    final parsed = parseNote(added.single);
    expect(parsed.body, 'line one\nline two');
    expect(parsed.tags, ['#work', '#drink']);
    // Draft clears; tags stay picked for the next note.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.text('Notes tagged #work #drink · 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
