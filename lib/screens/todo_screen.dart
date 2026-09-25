import 'package:flutter/material.dart';

import '../models.dart';
import '../frequency_cache.dart';
import '../utils.dart';

/// A todo entry paired with its optional scheduled (`#when`) date.
class _Todo {
  final WordEntry entry;
  final DateTime? due;
  final bool completed;

  _Todo(this.entry, this.due, this.completed);
}

/// The Todos tab: every `#todo` entry, scheduled ones first, with
/// checkboxes that write `#done` records.
class TodoScreen extends StatefulWidget {
  final List<WordEntry> entries;
  final EntryFrequencyCache cache;
  final VoidCallback? onOpenMenu;
  final Future<void> Function(String word) onAddEntry;
  final Future<void> Function(WordEntry entry) onCompleteTodo;
  final Future<void> Function(WordEntry entry) onDeleteEntry;
  final Future<void> Function(WordEntry entry) onEditEntry;

  const TodoScreen({
    super.key,
    required this.entries,
    required this.cache,
    required this.onAddEntry,
    required this.onCompleteTodo,
    required this.onDeleteEntry,
    required this.onEditEntry,
    this.onOpenMenu,
  });

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showCompleted = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isCompleted(WordEntry entry) =>
      widget.cache.isDoneHash(generateTodoHash(entry.word, entry.timestamp));

  List<_Todo> _collectTodos() {
    final todos = <_Todo>[];
    for (final entry in widget.entries) {
      if (!isTodoText(entry.word) || isDoneText(entry.word)) continue;
      final dates = extractWhenDates(entry.word);
      todos.add(_Todo(
        entry,
        dates.isEmpty ? null : dates.first,
        _isCompleted(entry),
      ));
    }
    return todos;
  }

  Future<void> _submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final word = isTodoText(trimmed) ? trimmed : '$trimmed #todo';
    _controller.clear();
    await widget.onAddEntry(word);
    if (mounted) _focusNode.requestFocus();
  }

  String _dueLabel(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    final diff = day.difference(today).inDays;
    if (diff < -1) return '${-diff}d overdue';
    if (diff == -1) return 'Yesterday';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return 'In ${diff}d';
    return DateTimeFormatter(due).date;
  }

  bool _isOverdue(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTodoTile(_Todo todo) {
    final entry = todo.entry;
    final text = stripTags(entry.word);

    return Dismissible(
      key: ValueKey('${entry.timestamp.toIso8601String()}|${entry.word}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDeleteEntry(entry),
      child: ListTile(
        leading: Checkbox(
          value: todo.completed,
          onChanged:
              todo.completed ? null : (_) => widget.onCompleteTodo(entry),
        ),
        title: Text(
          text.isEmpty ? entry.word : text,
          style: TextStyle(
            decoration: todo.completed ? TextDecoration.lineThrough : null,
            color: todo.completed ? Colors.grey : null,
          ),
        ),
        subtitle: Row(
          children: [
            if (todo.due != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _dueLabel(todo.due!),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isOverdue(todo.due!) && !todo.completed
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Text(
              DateTimeFormatter(entry.timestamp).daysAgo,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => widget.onEditEntry(entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todos = _collectTodos();
    final open = todos.where((t) => !t.completed).toList();
    final done = todos.where((t) => t.completed).toList();

    // Scheduled todos sorted by due date, unscheduled by newest first.
    final scheduled = open.where((t) => t.due != null).toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    final unscheduled = open.where((t) => t.due == null).toList()
      ..sort((a, b) => b.entry.timestamp.compareTo(a.entry.timestamp));
    done.sort((a, b) => b.entry.timestamp.compareTo(a.entry.timestamp));

    final items = <Widget>[];
    if (scheduled.isNotEmpty) {
      items.add(_sectionHeader('Scheduled', scheduled.length));
      items.addAll(scheduled.map(_buildTodoTile));
    }
    if (unscheduled.isNotEmpty) {
      items.add(_sectionHeader('Anytime', unscheduled.length));
      items.addAll(unscheduled.map(_buildTodoTile));
    }
    if (done.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon:
                  Icon(_showCompleted ? Icons.expand_less : Icons.expand_more),
              label: Text('Completed (${done.length})'),
              onPressed: () => setState(() => _showCompleted = !_showCompleted),
            ),
          ),
        ),
      );
      if (_showCompleted) items.addAll(done.map(_buildTodoTile));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenMenu,
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                labelText: 'Add a todo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.add_task),
              ),
              onSubmitted: _submit,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: open.isEmpty && done.isEmpty
                ? Center(
                    child: Text(
                      'Nothing to do.\nAdd a todo above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                    ),
                    children: items,
                  ),
          ),
        ],
      ),
    );
  }
}
