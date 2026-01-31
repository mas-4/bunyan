import 'package:flutter/material.dart';

import '../utils.dart';

class SettingsScreen extends StatefulWidget {
  final int aroundNowWindow;
  final int relatedEntriesWindow;
  final Function(int, int) onSave;

  const SettingsScreen({
    super.key,
    required this.aroundNowWindow,
    required this.relatedEntriesWindow,
    required this.onSave,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _aroundNowWindow;
  late int _relatedEntriesWindow;

  final List<int> _timeOptions = [15, 30, 45, 60, 90, 120, 180, 240];

  @override
  void initState() {
    super.initState();
    _aroundNowWindow = widget.aroundNowWindow;
    _relatedEntriesWindow = widget.relatedEntriesWindow;
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else if (minutes == 60) {
      return '1 hour';
    } else if (minutes % 60 == 0) {
      return '${minutes ~/ 60} hours';
    } else {
      return '${minutes ~/ 60}h ${minutes % 60}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_aroundNowWindow, _relatedEntriesWindow);
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Time Windows',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            title: Text('Around Now Window'),
            subtitle: Text(
              'Time range for suggestions based on current time\n± ${_formatMinutes(_aroundNowWindow)} (${_formatMinutes(_aroundNowWindow * 2)} total)',
            ),
            trailing: DropdownButton<int>(
              value: _aroundNowWindow,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _aroundNowWindow = value;
                  });
                }
              },
              items: _timeOptions.map((minutes) {
                return DropdownMenuItem(
                  value: minutes,
                  child: Text(_formatMinutes(minutes)),
                );
              }).toList(),
            ),
          ),
          Divider(),
          ListTile(
            title: Text('Related Entries Window'),
            subtitle: Text(
              'Time range for related entries in edit view\n± ${_formatMinutes(_relatedEntriesWindow)} (${_formatMinutes(_relatedEntriesWindow * 2)} total)',
            ),
            trailing: DropdownButton<int>(
              value: _relatedEntriesWindow,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _relatedEntriesWindow = value;
                  });
                }
              },
              items: _timeOptions.map((minutes) {
                return DropdownMenuItem(
                  value: minutes,
                  child: Text(_formatMinutes(minutes)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
