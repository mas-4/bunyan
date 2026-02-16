import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Habits', Icons.loop, [
            _p('Add @habit[SPEC] to any entry to track it as a habit. '
                'Completions are just duplicate entries with the same text.'),
            _sub('Interval (every N days/weeks/months)'),
            _code('@habit[1d]  @habit[2d]  @habit[7d]\n'
                '@habit[1w]  @habit[2w]\n'
                '@habit[1m]  @habit[3m]  @habit[1y]'),
            _sub('Frequency (N times per period)'),
            _code('@habit[2/d]  2x per day\n'
                '@habit[3/w]  3x per week\n'
                '@habit[2/m]  2x per month'),
            _sub('Sliding window'),
            _code('@habit[3 in 7d]  3 times in any 7-day window\n'
                '@habit[5 in 2w]  5 times in any 2-week window'),
            _sub('Calendar-anchored'),
            _code('@habit[every monday]\n'
                '@habit[every march]\n'
                '@habit[13th]           13th of every month\n'
                '@habit[march 13th]     specific date yearly'),
            _sub('Dependency (hash or tag)'),
            _code('@habit[after 7 a3f7]  activates after 7\n'
                '                      entries matching hash a3f7\n'
                '@habit[every 3 @run]  activates every 3 entries\n'
                '                      containing tag @run'),
            _p('Tag dependencies match any entry containing the tag, '
                'e.g. both "@run long" and "@run base" count toward '
                '@habit[every 3 @run]. The count resets after each completion.'),
            _sub('Rescheduling & ending'),
            _p('To change a schedule, add a new entry with the updated spec. '
                'The most recent entry per hash determines the current schedule.'),
            _code('@habit  (no brackets) = habit ended/paused'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Calendar tags', Icons.calendar_month, [
            _p('Use #when to attach a date/time to any entry. '
                'Typing #when auto-opens a date & time picker.'),
            _code('#when[2026-02-16 2:30:00 PM]'),
            _p('Entries with #when tags show a calendar icon in the edit screen '
                'to add the event to your system calendar.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Todos', Icons.check_circle_outline, [
            _p('Add #todo to any entry to mark it as a task.'),
            _code('buy groceries #todo'),
            _p('When filtering by #todo, completed todos are hidden. '
                'Tap the checkmark icon to mark a todo as done — this creates '
                'a #done entry with a reference hash.'),
            _p('Completed todos show with strikethrough text in the main list.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Content hashes', Icons.tag, [
            _p('Every entry gets a 4-character hex hash of its core content '
                '(with @habit[...] stripped). Hashes appear in:'),
            _bullet('Entry subtitle (e.g. 2:30 PM \u00b7 a3f7)'),
            _bullet('Edit entry screen'),
            _bullet('Entry stats screen'),
            _p('Hashes are used for cross-referencing — e.g. #done references '
                'and @habit[after N HASH] dependencies.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Pins & tags', Icons.push_pin, [
            _p('Add #pin to any entry to pin it to the top of the list.'),
            _p('Tag characters (!@#^&~+=\\|) trigger autocomplete suggestions '
                'from your existing entries.'),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
    );
  }

  Widget _sub(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _code(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.grey.shade800,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u2022 ', style: TextStyle(fontSize: 14)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
