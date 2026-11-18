import 'package:flutter/material.dart';

import '../frequency_cache.dart';
import '../models.dart';
import '../utils.dart';

/// Tags offered as one-tap chips when writing a note: tags already used on
/// notes (most used first), then the hotbar, then the most-used tags overall.
List<String> buildQuickTags({
  required List<WordEntry> entries,
  required EntryFrequencyCache cache,
  required List<String> hotbarTags,
  int limit = 24,
}) {
  final result = <String>[];
  final seen = <String>{};
  void add(String t) {
    if (t.length < 2 || !tagLeaders.contains(t[0]) || isSystemTag(t)) return;
    if (seen.add(t.toLowerCase())) result.add(t);
  }

  final noteCounts = <String, int>{};
  final display = <String, String>{};
  for (final e in entries) {
    if (!isNoteText(e.word)) continue;
    for (final t in noteDisplayTags(e.word)) {
      final k = t.toLowerCase();
      noteCounts[k] = (noteCounts[k] ?? 0) + 1;
      display.putIfAbsent(k, () => t);
    }
  }
  final byUse = noteCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in byUse) {
    add(display[e.key]!);
  }
  hotbarTags.forEach(add);
  for (final e in cache.getTagsSortedByFrequency()) {
    if (result.length >= limit) break;
    add(e.key);
  }
  return result;
}

/// Open the note editor for a new note or [existing], then persist the
/// result through the supplied callbacks.
Future<void> openNoteEditor(
  BuildContext context, {
  WordEntry? existing,
  required List<String> quickTags,
  Iterable<String> initialTags = const [],
  required Future<void> Function(String word) onAdd,
  required Future<void> Function(WordEntry oldEntry, WordEntry newEntry) onUpdate,
  required Future<void> Function(WordEntry entry) onDelete,
}) async {
  final parsed = existing == null ? null : parseNote(existing.word);
  final result = await Navigator.push<NoteEditorResult>(
    context,
    MaterialPageRoute(
      builder: (_) => NoteEditorScreen(
        initialBody: parsed?.body ?? '',
        initialTags: parsed?.tags ?? initialTags.toList(),
        quickTags: quickTags,
        timestamp: existing?.timestamp,
      ),
    ),
  );
  if (result == null) return;

  if (result.delete) {
    if (existing != null) await onDelete(existing);
    return;
  }
  final text = buildNoteText(result.body, result.tags);
  if (existing == null) {
    await onAdd(text);
  } else if (text != existing.word) {
    await onUpdate(existing, WordEntry(word: text, timestamp: existing.timestamp));
  }
}

/// Ask for a new tag name. Returns it normalised (no spaces, `#` added when
/// it doesn't start with a tag character), or null if cancelled/invalid.
Future<String?> promptForTag(BuildContext context) async {
  final controller = TextEditingController();
  final raw = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add tag'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '#idea',
          helperText: 'Starts with # unless you use another tag character',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (raw == null) return null;
  var tag = raw.trim().replaceAll(RegExp(r'\s+'), '-');
  if (tag.isEmpty) return null;
  if (!tagLeaders.contains(tag[0])) tag = '#$tag';
  if (tag.length < 2 || tag.toLowerCase() == noteTag) return null;
  return tag;
}

/// The Notes tab. Works like Log: a composer at the top (a roomy text box
/// plus quick-tag chips) saves straight into the list below. The selected
/// chips tag the note being written *and* filter the list, so you see the
/// notes you're writing alongside.
class NotesScreen extends StatefulWidget {
  final List<WordEntry> entries;
  final EntryFrequencyCache cache;
  final List<String> hotbarTags;
  final VoidCallback? onOpenMenu;
  final Future<void> Function(String word) onAddEntry;
  final Future<void> Function(WordEntry oldEntry, WordEntry newEntry) onUpdateEntry;
  final Future<void> Function(WordEntry entry) onDeleteEntry;

  const NotesScreen({
    super.key,
    required this.entries,
    required this.cache,
    required this.hotbarTags,
    required this.onAddEntry,
    required this.onUpdateEntry,
    required this.onDeleteEntry,
    this.onOpenMenu,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  bool _saving = false;

  /// Quick tags picked in the composer, in pick order. They stay selected
  /// after saving so a run of notes can share them; they also filter the list.
  final List<String> _selected = [];

  /// Tags created with "+ Tag" that aren't in the log yet.
  final List<String> _customTags = [];

  // Memoized scans of the full entry list, redone only when the data changes
  // (cache revision) — not on every chip tap or search keystroke.
  int? _memoRevision;
  List<String>? _memoHotbar;
  List<WordEntry> _notes = const [];
  List<String> _quickTags = const [];

  void _refreshMemo() {
    final revision = widget.cache.revision;
    if (revision == _memoRevision && identical(widget.hotbarTags, _memoHotbar)) {
      return;
    }
    _memoRevision = revision;
    _memoHotbar = widget.hotbarTags;
    _notes = widget.entries.where((e) => isNoteText(e.word)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _quickTags = buildQuickTags(
      entries: _notes,
      cache: widget.cache,
      hotbarTags: widget.hotbarTags,
    );
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isSelected(String tag) =>
      _selected.any((t) => t.toLowerCase() == tag.toLowerCase());

  void _toggle(String tag) {
    setState(() {
      if (_isSelected(tag)) {
        _selected.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
      } else {
        _selected.add(tag);
      }
    });
  }

  Future<void> _addCustomTag() async {
    final tag = await promptForTag(context);
    if (tag == null || !mounted) return;
    setState(() {
      if (!_customTags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        _customTags.insert(0, tag);
      }
      if (!_isSelected(tag)) _selected.add(tag);
    });
  }

  Future<void> _submit() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onAddEntry(buildNoteText(body, _selected));
      _composer.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEditor(WordEntry existing) {
    return openNoteEditor(
      context,
      existing: existing,
      quickTags: _quickTags,
      onAdd: widget.onAddEntry,
      onUpdate: widget.onUpdateEntry,
      onDelete: widget.onDeleteEntry,
    );
  }

  Future<bool> _confirmDelete(WordEntry note) async {
    final preview = entryDisplayText(note.word).split('\n').first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note'),
        content: Text('Delete "$preview"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    _refreshMemo();
    final notes = _notes;

    final filter = _selected.map((t) => t.toLowerCase()).toSet();
    final query = _searchController.text.trim();
    final visible = notes.where((n) {
      if (filter.isNotEmpty) {
        final tags = noteDisplayTags(n.word).map((t) => t.toLowerCase()).toSet();
        if (!filter.every(tags.contains)) return false;
      }
      if (query.isNotEmpty && !matchesSearch(decodeNoteLines(n.word), query)) {
        return false;
      }
      return true;
    }).toList();
    final ordered = [
      ...visible.where((n) => isPinnedText(n.word)),
      ...visible.where((n) => !isPinnedText(n.word)),
    ];

    // Chip options: picked tags first, then new custom ones, then suggestions.
    final seen = <String>{};
    final options = [
      for (final t in [
        ..._selected,
        ..._customTags,
        ..._quickTags,
      ])
        if (seen.add(t.toLowerCase())) t,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: widget.onOpenMenu == null
            ? null
            : IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenMenu),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text('Notes${notes.isEmpty ? '' : ' (${notes.length})'}'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
          ),
        ],
      ),
      // The composer is the list's first item, so it scrolls away while
      // reading and comes back when you scroll to the top — like Log.
      body: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24),
        itemCount: 2 + (ordered.isEmpty ? 1 : ordered.length),
        itemBuilder: (context, i) {
          if (i == 0) return _composerCard(context, options);
          if (i == 1) return _listHeader(context, notes.length, ordered.length);
          if (ordered.isEmpty) {
            return _emptyState(context, hasNotes: notes.isNotEmpty);
          }
          return _noteCard(context, ordered[i - 2]);
        },
      ),
    );
  }

  Widget _composerCard(BuildContext context, List<String> options) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _composer,
            focusNode: _composerFocus,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Write a note…\nThe first line becomes its title.',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 48, 12),
              suffixIcon: Align(
                widthFactor: 1,
                heightFactor: 1,
                alignment: Alignment.bottomRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _composer,
                  builder: (context, value, _) {
                    final canSave = value.text.trim().isNotEmpty && !_saving;
                    return IconButton(
                      icon: const Icon(Icons.send),
                      tooltip: 'Save note',
                      color: theme.colorScheme.primary,
                      onPressed: canSave ? _submit : null,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(t),
                      selected: _isSelected(t),
                      onSelected: (_) => _toggle(t),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Tag'),
                  onPressed: _addCustomTag,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader(BuildContext context, int total, int shown) {
    final filtered = _selected.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filtered
                  ? 'Notes tagged ${_selected.join(' ')} · $shown'
                  : 'All notes · $total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          if (filtered)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear tags'),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, {required bool hasNotes}) {
    final filtered = _selected.isNotEmpty || _searchController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
      child: Column(
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            hasNotes && filtered
                ? 'No notes with these tags yet — the next one you save will be.'
                : 'No notes yet. Notes are regular entries tagged #note, so '
                    'they show up in Log and search too.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(BuildContext context, WordEntry note) {
    final theme = Theme.of(context);
    final parsed = parseNote(note.word);
    final lines = parsed.body.split('\n');
    final hasTitle = lines.length > 1;
    final rest = hasTitle ? lines.skip(1).join('\n').trim() : parsed.body;
    final tags = noteDisplayTags(note.word);
    final dt = DateTimeFormatter(note.timestamp);

    return Dismissible(
      key: ValueKey('note_${note.timestamp.microsecondsSinceEpoch}_${note.word.hashCode}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(note),
      onDismissed: (_) => widget.onDeleteEntry(note),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openEditor(note),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTitle)
                  Text(
                    lines.first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (rest.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: hasTitle ? 4 : 0),
                    child: Text(
                      rest,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in tags)
                        _TagPill(
                          tag: t,
                          active: _isSelected(t),
                          onTap: () => _toggle(t),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${dt.weekDay} ${dt.date} · ${dt.time} · ${dt.daysAgo}',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ),
                    if (isPinnedText(note.word))
                      Icon(Icons.push_pin, size: 16, color: Colors.grey.shade500),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final String tag;
  final bool active;
  final VoidCallback onTap;

  const _TagPill({required this.tag, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 12,
            color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// What the note editor hands back: the text and picked tags, or a delete.
class NoteEditorResult {
  final String body;
  final List<String> tags;
  final bool delete;

  const NoteEditorResult({this.body = '', this.tags = const [], this.delete = false});
}

/// Full-screen note writer with a quick-tag picker docked above the keyboard.
class NoteEditorScreen extends StatefulWidget {
  final String initialBody;
  final List<String> initialTags;
  final List<String> quickTags;

  /// When the note was written; null for a new note.
  final DateTime? timestamp;

  const NoteEditorScreen({
    super.key,
    required this.initialBody,
    required this.initialTags,
    required this.quickTags,
    this.timestamp,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _controller;
  late final List<String> _options;
  late final List<String> _selected;

  bool get _isEditing => widget.timestamp != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBody);
    _selected = [...widget.initialTags];
    // Selected tags lead, so a note's own tags are visible without scrolling.
    final seen = <String>{};
    _options = [
      for (final t in [..._selected, ...widget.quickTags])
        if (seen.add(t.toLowerCase())) t,
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isSelected(String tag) =>
      _selected.any((t) => t.toLowerCase() == tag.toLowerCase());

  bool get _dirty {
    if (_controller.text.trim() != widget.initialBody.trim()) return true;
    final a = _selected.map((t) => t.toLowerCase()).toSet();
    final b = widget.initialTags.map((t) => t.toLowerCase()).toSet();
    return a.length != b.length || !a.containsAll(b);
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  void _toggle(String tag) {
    setState(() {
      if (_isSelected(tag)) {
        _selected.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
      } else {
        _selected.add(tag);
      }
    });
  }

  Future<void> _addCustomTag() async {
    final tag = await promptForTag(context);
    if (tag == null || !mounted) return;
    setState(() {
      if (!_options.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        _options.insert(0, tag);
      }
      if (!_isSelected(tag)) _selected.add(tag);
    });
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      NoteEditorResult(body: _controller.text, tags: List.of(_selected)),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note'),
        content: const Text('This removes the note from your log.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, const NoteEditorResult(delete: true));
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = widget.timestamp;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit note' : 'New note'),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: _delete,
              ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _canSave ? _save : null,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ts != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    () {
                      final dt = DateTimeFormatter(ts);
                      return 'Written ${dt.weekDay} ${dt.date} · ${dt.time}';
                    }(),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _controller,
                    autofocus: !_isEditing,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Write a note…\n\nThe first line becomes its title.',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const Divider(height: 1),
              _quickTagPicker(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickTagPicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                const Text(
                  'QUICK TAGS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                if (_selected.isNotEmpty)
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final t in _options)
                    FilterChip(
                      label: Text(t),
                      selected: _isSelected(t),
                      onSelected: (_) => _toggle(t),
                      visualDensity: VisualDensity.compact,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Tag'),
                    onPressed: _addCustomTag,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
