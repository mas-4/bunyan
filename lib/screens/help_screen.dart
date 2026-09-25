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
          _section(context, 'Tabs', Icons.tab, [
            _p('Bunyan has four tabs along the bottom:'),
            _bullet('Habits — the grid of @habit entries and their day cells'),
            _bullet('Todos — every open #todo, scheduled ones first'),
            _bullet('Log — the full timestamped entry list and quick entry field'),
            _bullet('Stats — totals, what you log around this time, most logged'),
            _p('Import, export, backups, and configuration live in the menu '
                'behind the icon at the top left of any tab.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Todos', Icons.check_circle_outline, [
            _p('Add #todo to any entry to mark it as a task. Anything typed '
                'on the Todos tab gets #todo added automatically.'),
            _code('buy groceries #todo'),
            _p('Tap a checkbox to complete a todo — this creates a #done '
                'entry with a reference hash, so the original log stays intact.'),
            _p('Add a #when tag to schedule a todo; it then sorts by due date '
                'and shows overdue in red.'),
            _p('Completed todos show with strikethrough text.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Symptoms', Icons.monitor_heart_outlined, [
            _p('Add @symptom to any entry to track it as a symptom.'),
            _code('headache @symptom\n'
                'nausea @symptom'),
            _p('When you tap a @symptom entry to view its stats, '
                'a "Potential Triggers" section appears showing entries '
                'that occurred in the 24 hours before each symptom occurrence.'),
            _p('Triggers are ranked using a lift score — entries that appear '
                'disproportionately often before your symptom (compared to '
                'their overall frequency) rank highest. Log more entries '
                'for better accuracy.'),
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
          const SizedBox(height: 24),
          _section(context, 'Habits', Icons.loop, [
            _p('See the Habits screen for full syntax documentation — '
                'tap the help icon in the Habits app bar.'),
          ]),
          const SizedBox(height: 24),
          _section(context, 'Scheduling with #when', Icons.schedule, [
            _p('Use #when to attach a date and time to any entry. Typing '
                '#when auto-opens a date & time picker.'),
            _code('#when[2026-02-16 2:30:00 PM]'),
            _p('Scheduled todos appear under Scheduled on the Todos tab, '
                'ordered by due date.'),
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
