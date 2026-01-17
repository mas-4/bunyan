class DateTimeFormatter {
  final DateTime dateTime;

  DateTimeFormatter(this.dateTime);

  String get date {
    final y = dateTime.year;
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  String get weekDay {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dateTime.weekday - 1]; // weekday is 1-7, array is 0-6
  }

  String get time {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12; // Midnight = 12 AM
    } else if (hour > 12) {
      hour = hour - 12; // Convert to 12-hour
    }
    String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String get daysAgo {
    final tmp = DateTime.now();
    final today = DateTime(tmp.year, tmp.month, tmp.day);
    final calendarDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final daysAgo = today.difference(calendarDate).inDays;

    if (daysAgo == 0) {
      return 'Today';
    } else if (daysAgo == 1) {
      return 'Yesterday';
    }
    return '${daysAgo}d ago';
  }
}

class WordEntry {
  final String word;
  final DateTime timestamp;

  WordEntry({required this.word, required this.timestamp});

  String toCsv() {
    return '"${timestamp.toIso8601String()}","$word"';
  }

  static WordEntry fromCsv(String csvLine) {
    // Simple CSV parsing - handles quoted fields
    final parts = csvLine.split('","');
    final timestampStr = parts[0].replaceAll('"', '');
    final word = parts[1].replaceAll('"', '');
    return WordEntry(word: word, timestamp: DateTime.parse(timestampStr));
  }
}
