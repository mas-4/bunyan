import 'package:flutter/material.dart';

class TagManagerScreen extends StatefulWidget {
  final List<MapEntry<String, int>> tagsByFrequency;

  const TagManagerScreen({
    super.key,
    required this.tagsByFrequency,
  });

  @override
  State<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends State<TagManagerScreen> {
  // oldTag -> newTag
  final Map<String, String> _renames = {};

  List<MapEntry<String, int>> get _sortedTags {
    final tags = widget.tagsByFrequency.map((e) {
      final displayName = _renames[e.key] ?? e.key;
      return MapEntry(e.key, MapEntry(displayName, e.value));
    }).toList();
    tags.sort(
        (a, b) => a.value.key.toLowerCase().compareTo(b.value.key.toLowerCase()));
    return tags.map((e) => MapEntry(e.key, e.value.value)).toList();
  }

  String _displayName(String originalTag) {
    return _renames[originalTag] ?? originalTag;
  }

  Future<void> _showRenameDialog(String originalTag) async {
    final currentName = _displayName(originalTag);
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename Tag'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'New tag name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;

    setState(() {
      if (newName == originalTag) {
        // Reverted to original name, remove from renames
        _renames.remove(originalTag);
      } else {
        _renames[originalTag] = newName;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedTags = _sortedTags;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Manage Tags'),
          actions: [
            if (_renames.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(context, _renames),
                child: Text('Apply (${_renames.length})',
                    style: TextStyle(color: Colors.blue)),
              ),
          ],
        ),
        body: sortedTags.isEmpty
            ? Center(
                child: Text(
                  'No tags found.\nAdd entries with tags like #tag, @mention, etc.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: sortedTags.length,
                itemBuilder: (context, index) {
                  final originalTag = sortedTags[index].key;
                  final count = sortedTags[index].value;
                  final displayName = _displayName(originalTag);
                  final isRenamed = _renames.containsKey(originalTag);

                  return ListTile(
                    title: Text(displayName),
                    subtitle: Text(
                      isRenamed
                          ? 'was: $originalTag  |  $count use${count != 1 ? 's' : ''}'
                          : '$count use${count != 1 ? 's' : ''}',
                    ),
                    trailing: Icon(Icons.edit, color: Colors.grey),
                    onTap: () => _showRenameDialog(originalTag),
                  );
                },
              ),
      ),
    );
  }
}
