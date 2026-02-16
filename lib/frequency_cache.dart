import 'models.dart';
import 'utils.dart';

/// Centralized cache for entry frequency data.
///
/// Provides O(1) lookups for word counts, tag frequencies, and done hashes.
/// Built once on app load and updated incrementally when entries change.
class EntryFrequencyCache {
  /// Word -> count mapping for duplicate detection
  final Map<String, int> _wordCounts = {};

  /// Tag -> count mapping for tag frequency sorting
  final Map<String, int> _tagCounts = {};

  /// Set of done hashes for O(1) todo completion checks
  final Set<String> _doneHashes = {};

  /// Content hash -> sorted list of completion timestamps for habit tracking
  final Map<String, List<DateTime>> _habitCompletions = {};

  /// Build the cache from scratch using a list of entries.
  /// Call this on app load.
  void buildFromEntries(List<WordEntry> entries) {
    _wordCounts.clear();
    _tagCounts.clear();
    _doneHashes.clear();
    _habitCompletions.clear();

    for (final entry in entries) {
      _addEntryToCache(entry);
    }
  }

  /// Add a single entry to the cache.
  /// Call this when a new entry is created.
  void addEntry(WordEntry entry) {
    _addEntryToCache(entry);
  }

  /// Remove a single entry from the cache.
  /// Call this when an entry is deleted.
  void removeEntry(WordEntry entry) {
    _removeEntryFromCache(entry);
  }

  /// Get the count of entries with the exact word.
  int getWordCount(String word) {
    return _wordCounts[word] ?? 0;
  }

  /// Get the count of a specific tag.
  int getTagCount(String tag) {
    return _tagCounts[tag] ?? 0;
  }

  /// Check if a hash exists in the done hashes set.
  bool isDoneHash(String hash) {
    return _doneHashes.contains(hash);
  }

  /// Get all tags sorted by frequency (descending).
  List<MapEntry<String, int>> getTagsSortedByFrequency() {
    final sortedEntries = _tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedEntries;
  }

  /// Get habit completions for a content hash.
  List<DateTime> getHabitCompletions(String hash) {
    return _habitCompletions[hash] ?? [];
  }

  /// Get the count of habit completions for a content hash.
  int getHabitCompletionCount(String hash) {
    return _habitCompletions[hash]?.length ?? 0;
  }

  /// Get all habit completion data (hash -> timestamps).
  Map<String, List<DateTime>> get allHabitCompletions => _habitCompletions;

  /// Get all tag suggestions for a given tag character and optional partial match.
  List<String> getTagSuggestions(String tagChar, [String partialTag = '']) {
    final matchingTags = _tagCounts.keys
        .where((tag) => tag.startsWith(tagChar))
        .toList();

    if (partialTag.isNotEmpty) {
      return matchingTags
          .where((tag) => tag.toLowerCase().startsWith(partialTag.toLowerCase()))
          .toList();
    }

    return matchingTags;
  }

  void _addEntryToCache(WordEntry entry) {
    // Update word count
    _wordCounts[entry.word] = (_wordCounts[entry.word] ?? 0) + 1;

    // Extract and count tags
    _extractAndUpdateTags(entry.word, 1);

    // Update done hashes
    _updateDoneHash(entry, true);

    // Track habit completions
    if (isHabitEntry(entry.word)) {
      final hash = generateContentHash(entry.word);
      _habitCompletions.putIfAbsent(hash, () => []);
      _habitCompletions[hash]!.add(entry.timestamp);
      _habitCompletions[hash]!.sort();
    }
  }

  void _removeEntryFromCache(WordEntry entry) {
    // Update word count
    final currentCount = _wordCounts[entry.word] ?? 0;
    if (currentCount <= 1) {
      _wordCounts.remove(entry.word);
    } else {
      _wordCounts[entry.word] = currentCount - 1;
    }

    // Extract and decrement tags
    _extractAndUpdateTags(entry.word, -1);

    // Update done hashes
    _updateDoneHash(entry, false);

    // Remove habit completion
    if (isHabitEntry(entry.word)) {
      final hash = generateContentHash(entry.word);
      _habitCompletions[hash]?.remove(entry.timestamp);
      if (_habitCompletions[hash]?.isEmpty ?? false) {
        _habitCompletions.remove(hash);
      }
    }
  }

  void _extractAndUpdateTags(String word, int delta) {
    // Collapse #when[...] and @habit[...] so bracket content doesn't fragment into tags
    var collapsed = word.replaceAll(whenTagRegex, '#when');
    collapsed = collapsed.replaceAll(habitTagRegex, '@habit');
    final words = collapsed.split(' ');
    for (final w in words) {
      if (w.isNotEmpty && tagLeaders.contains(w[0])) {
        final currentCount = _tagCounts[w] ?? 0;
        final newCount = currentCount + delta;
        if (newCount <= 0) {
          _tagCounts.remove(w);
        } else {
          _tagCounts[w] = newCount;
        }
      }
    }
  }

  void _updateDoneHash(WordEntry entry, bool adding) {
    if (entry.word.toLowerCase().startsWith('#done ')) {
      final parts = entry.word.split(' ');
      if (parts.length >= 2) {
        final hash = parts[1].toLowerCase();
        if (adding) {
          _doneHashes.add(hash);
        } else {
          _doneHashes.remove(hash);
        }
      }
    }
  }
}
