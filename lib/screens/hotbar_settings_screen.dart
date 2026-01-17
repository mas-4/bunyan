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

  @override
  void initState() {
    super.initState();
    _selectedTags = List.from(widget.currentHotbarTags);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hotbar Settings'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, _selectedTags.take(5).toList());
            },
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Select up to 5 tags for your hotbar. Tags are sorted by frequency.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '${_selectedTags.length}/5 tags selected',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _selectedTags.length > 5 ? Colors.red : null,
              ),
            ),
          ),
          Divider(),
          Expanded(
            child: widget.tagsByFrequency.isEmpty
                ? Center(
                    child: Text(
                      'No tags found.\nAdd entries with tags like #tag, @mention, etc.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.tagsByFrequency.length,
                    itemBuilder: (context, index) {
                      final entry = widget.tagsByFrequency[index];
                      final tag = entry.key;
                      final count = entry.value;
                      final isSelected = _selectedTags.contains(tag);

                      return CheckboxListTile(
                        title: Text(tag),
                        subtitle: Text(
                          'Used $count time${count != 1 ? 's' : ''}',
                        ),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              if (_selectedTags.length < 5) {
                                _selectedTags.add(tag);
                              }
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
