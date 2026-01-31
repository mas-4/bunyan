import 'package:flutter/material.dart';

class HotbarSettingsScreen extends StatefulWidget {
  final List<String> currentHotbarTags;
  final List<MapEntry<String, int>> tagsByFrequency;

  const HotbarSettingsScreen({
    super.key,
    required this.currentHotbarTags,
    required this.tagsByFrequency,
  });

  @override
  State<HotbarSettingsScreen> createState() => _HotbarSettingsScreenState();
}

class _HotbarSettingsScreenState extends State<HotbarSettingsScreen> {
  late List<String> _selectedTags;
  final TextEditingController _customTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTags = List.from(widget.currentHotbarTags);
  }

  @override
  void dispose() {
    _customTagController.dispose();
    super.dispose();
  }

  void _addCustomTag() {
    final tag = _customTagController.text.trim();
    if (tag.isNotEmpty && !_selectedTags.contains(tag)) {
      setState(() {
        _selectedTags.add(tag);
        _customTagController.clear();
      });
    }
  }

  List<MapEntry<String, int>> get _availableTags {
    return widget.tagsByFrequency
        .where((entry) => !_selectedTags.contains(entry.key))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hotbar Settings'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, _selectedTags.toList());
            },
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected tags section - reorderable
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Your Hotbar (drag to reorder)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_selectedTags.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'No tags selected. Add some from below.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
            )
          else
            Container(
              constraints: BoxConstraints(maxHeight: 250),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _selectedTags.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final tag = _selectedTags.removeAt(oldIndex);
                    _selectedTags.insert(newIndex, tag);
                  });
                },
                itemBuilder: (context, index) {
                  final tag = _selectedTags[index];
                  return ListTile(
                    key: ValueKey(tag),
                    leading: Icon(Icons.drag_handle),
                    title: Text(tag),
                    trailing: IconButton(
                      icon: Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedTags.remove(tag);
                        });
                      },
                    ),
                  );
                },
              ),
            ),

          // Custom tag input
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTagController,
                    decoration: InputDecoration(
                      hintText: 'Add custom entry...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _addCustomTag(),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle, color: Colors.green),
                  onPressed: _addCustomTag,
                ),
              ],
            ),
          ),

          Divider(height: 32),

          // Available tags section
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Available Tags (by frequency)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _availableTags.isEmpty
                ? Center(
                    child: Text(
                      widget.tagsByFrequency.isEmpty
                          ? 'No tags found.\nAdd entries with tags like #tag, @mention, etc.'
                          : 'All tags added to hotbar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _availableTags.length,
                    itemBuilder: (context, index) {
                      final entry = _availableTags[index];
                      final tag = entry.key;
                      final count = entry.value;

                      return ListTile(
                        title: Text(tag),
                        subtitle: Text('Used $count time${count != 1 ? 's' : ''}'),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle_outline, color: Colors.green),
                          onPressed: () {
                            setState(() {
                              _selectedTags.add(tag);
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
