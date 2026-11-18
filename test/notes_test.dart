import 'package:flutter_test/flutter_test.dart';
import 'package:bunyan/models.dart';
import 'package:bunyan/utils.dart';

void main() {
  group('isNoteText', () {
    test('matches a standalone #note tag anywhere', () {
      expect(isNoteText('idea #note'), isTrue);
      expect(isNoteText('#note idea'), isTrue);
      expect(isNoteText('IDEA #NOTE #work'), isTrue);
    });

    test('ignores tags that merely start with #note', () {
      expect(isNoteText('read my #notes'), isFalse);
      expect(isNoteText('#notebook bought'), isFalse);
    });
  });

  group('buildNoteText / parseNote', () {
    test('single line with quick tags', () {
      final text = buildNoteText('Call Dana', ['#work', '@dana']);
      expect(text, 'Call Dana #note #work @dana');
      final parsed = parseNote(text);
      expect(parsed.body, 'Call Dana');
      expect(parsed.tags, ['#work', '@dana']);
    });

    test('multi-line bodies survive a CSV round trip on one line', () {
      const body = 'Groceries\n- eggs\n\n#urgent milk';
      final text = buildNoteText(body, ['#home']);
      expect(text.contains('\n'), isFalse);

      final restored = WordEntry.fromCsv(
        WordEntry(word: text, timestamp: DateTime(2026, 11, 18, 9)).toCsv(),
      );
      final parsed = parseNote(restored.word);
      expect(parsed.body, body);
      expect(parsed.tags, ['#home']);
    });

    test('a tag starting a line is still its own space-delimited word', () {
      final text = buildNoteText('first\n#idea second', const []);
      expect(text.split(' '), contains('#idea'));
    });

    test('does not repeat tags already written inline', () {
      final text = buildNoteText('ship it #work', ['#Work', '#later']);
      expect(text, 'ship it #work #note #later');
    });

    test('strips a #note the user typed into the body', () {
      final text = buildNoteText('#note thoughts', const []);
      expect(text, 'thoughts #note');
    });

    test('hand-typed log entries with words after #note keep them in the body', () {
      final parsed = parseNote('#note remember the thing #todo');
      expect(parsed.body, 'remember the thing');
      expect(parsed.tags, ['#todo']);
    });

    test('keeps a #when tag intact as one tag', () {
      final parsed = parseNote('dentist #note #when[2026-11-20 2:30:00 PM]');
      expect(parsed.tags, ['#when[2026-11-20 2:30:00 PM]']);
    });
  });

  group('noteDisplayTags / entryDisplayText', () {
    test('display tags exclude #note', () {
      expect(noteDisplayTags('a #note #work @x'), ['#work', '@x']);
    });

    test('done records show just the todo text', () {
      expect(entryDisplayText('#done abcd1234 buy milk'), 'buy milk');
    });

    test('notes show the decoded body', () {
      expect(entryDisplayText(buildNoteText('a\nb', ['#x'])), 'a\nb');
    });
  });

  group('extractTags', () {
    test('collapses #when and @habit specs and de-duplicates', () {
      expect(
        extractTags('run @habit[3/w] #fit #FIT #when[2026-01-01 9:00:00 AM]'),
        ['@habit', '#fit', '#when'],
      );
    });
  });
}
