import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models.dart';

class EntryStatsScreen extends StatelessWidget {
  final String entryWord;
  final List<WordEntry> allEntries;

  const EntryStatsScreen({
    super.key,
    required this.entryWord,
    required this.allEntries,
  });

  List<WordEntry> get _matchingEntries {
    final word = entryWord.trim();
    final matches = allEntries.where((e) => e.word.trim() == word).toList();
    matches.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Most recent first
    return matches;
  }

  List<int> _getWeekdayFrequency(List<WordEntry> entries) {
    final counts = List.filled(7, 0);
    for (final entry in entries) {
      counts[entry.timestamp.weekday - 1]++;
    }
    return counts;
  }

  List<int> _getTimePeriodFrequency(List<WordEntry> entries) {
    final counts = List.filled(5, 0);
    for (final entry in entries) {
      final hour = entry.timestamp.hour;
      if (hour >= 5 && hour < 11) {
        counts[0]++;
      } else if (hour >= 11 && hour < 14) {
        counts[1]++;
      } else if (hour >= 14 && hour < 17) {
        counts[2]++;
      } else if (hour >= 17 && hour < 21) {
        counts[3]++;
      } else {
        counts[4]++;
      }
    }
    return counts;
  }

  List<MapEntry<DateTime, int>> _getWeeklyTrend(List<WordEntry> entries) {
    if (entries.isEmpty) return [];

    final weekCounts = <DateTime, int>{};
    for (final entry in entries) {
      // Get the start of the week (Monday)
      final date = entry.timestamp;
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final weekKey = DateTime(weekStart.year, weekStart.month, weekStart.day);
      weekCounts[weekKey] = (weekCounts[weekKey] ?? 0) + 1;
    }

    if (weekCounts.isEmpty) return [];

    // Find the range from first entry to current week
    final sortedKeys = weekCounts.keys.toList()..sort();
    final firstWeek = sortedKeys.first;
    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final lastWeek = DateTime(currentWeekStart.year, currentWeekStart.month, currentWeekStart.day);

    // Fill in all weeks from first to current, including gaps
    final result = <MapEntry<DateTime, int>>[];
    var week = firstWeek;
    while (!week.isAfter(lastWeek)) {
      result.add(MapEntry(week, weekCounts[week] ?? 0));
      week = week.add(Duration(days: 7));
    }

    return result;
  }

  List<int> _getWeeklyHeatmap(List<WordEntry> entries) {
    // 28 slots: 7 days × 4 periods (6 hours each)
    // Order: Morning (6-12), Afternoon (12-18), Evening (18-24), Night (0-6)
    // Starting with Sunday at the top
    final counts = List.filled(28, 0);

    for (final entry in entries) {
      // DateTime.weekday: 1=Monday, 7=Sunday. We want Sunday=0
      final dayIndex = entry.timestamp.weekday % 7; // Sunday=0, Monday=1, etc.
      final hour = entry.timestamp.hour;

      int periodIndex;
      if (hour >= 6 && hour < 12) {
        periodIndex = 0; // Morning
      } else if (hour >= 12 && hour < 18) {
        periodIndex = 1; // Afternoon
      } else if (hour >= 18) {
        periodIndex = 2; // Evening
      } else {
        periodIndex = 3; // Night (0-6)
      }

      final slotIndex = dayIndex * 4 + periodIndex;
      counts[slotIndex]++;
    }

    return counts;
  }

  bool get _isSymptom => entryWord.toLowerCase().contains('@symptom');

  String _dayKey(DateTime dt) => '${dt.year}-${dt.month}-${dt.day}';

  /// TF-IDF inspired trigger analysis.
  /// "TF" = how often an entry appears in the 24h before the symptom.
  /// "IDF" = penalize entries that appear on most days anyway.
  /// Lift = P(entry before symptom) / P(entry on any day). Lift > 1 = real signal.
  List<Map<String, dynamic>> _getTriggerAnalysis(
    List<WordEntry> symptomEntries, {
    int windowHours = 24,
  }) {
    if (symptomEntries.length < 2) return [];

    final symptomWord = entryWord.trim().toLowerCase();
    final totalSymptoms = symptomEntries.length;

    // Step 1: Count how many unique days each entry appears on (baseline frequency)
    final totalDays = allEntries.map((e) => _dayKey(e.timestamp)).toSet().length;
    final entryDays = <String, Set<String>>{}; // key -> set of day keys
    for (final entry in allEntries) {
      final key = entry.word.split(':')[0].trim();
      if (key.toLowerCase() == symptomWord) continue;
      entryDays.putIfAbsent(key, () => {});
      entryDays[key]!.add(_dayKey(entry.timestamp));
    }

    // Step 2: For each symptom occurrence, find entries in the lookback window
    final triggerCounts = <String, int>{}; // key -> symptom occurrences preceded by this entry
    final triggerLeadTimes = <String, List<Duration>>{};

    for (final symptom in symptomEntries) {
      final windowStart = symptom.timestamp.subtract(Duration(hours: windowHours));
      final seenForThis = <String>{};

      for (final entry in allEntries) {
        final word = entry.word.trim();
        if (word.toLowerCase() == symptomWord) continue;
        if (entry.timestamp.isBefore(windowStart)) continue;
        if (entry.timestamp.isAfter(symptom.timestamp)) continue;

        final key = word.split(':')[0].trim();
        if (key.isEmpty || seenForThis.contains(key)) continue;

        seenForThis.add(key);
        triggerCounts[key] = (triggerCounts[key] ?? 0) + 1;
        triggerLeadTimes.putIfAbsent(key, () => []);
        triggerLeadTimes[key]!.add(symptom.timestamp.difference(entry.timestamp));
      }
    }

    // Step 3: Calculate lift for each potential trigger
    final results = <Map<String, dynamic>>[];
    for (final entry in triggerCounts.entries) {
      if (entry.value < 2) continue;

      final triggerRate = entry.value / totalSymptoms;
      final daysWithEntry = entryDays[entry.key]?.length ?? 1;
      final baselineRate = daysWithEntry / totalDays;
      final lift = baselineRate > 0 ? triggerRate / baselineRate : 0.0;

      final leadTimes = triggerLeadTimes[entry.key]!;
      final avgLeadMinutes = leadTimes.fold<int>(0, (s, d) => s + d.inMinutes) ~/ leadTimes.length;

      results.add({
        'word': entry.key,
        'count': entry.value,
        'rate': triggerRate,
        'baselineRate': baselineRate,
        'lift': lift,
        'avgLead': Duration(minutes: avgLeadMinutes),
      });
    }

    // Sort by lift descending — high lift = unusual before symptoms
    results.sort((a, b) => (b['lift'] as double).compareTo(a['lift'] as double));
    return results;
  }

  Map<String, dynamic> _getStats(List<WordEntry> entries) {
    if (entries.isEmpty) {
      return {'count': 0};
    }

    final sorted = List<WordEntry>.from(entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final gaps = <Duration>[];
    for (int i = 1; i < sorted.length; i++) {
      gaps.add(sorted[i].timestamp.difference(sorted[i - 1].timestamp));
    }

    Duration? avgGap;
    if (gaps.isNotEmpty) {
      final totalMinutes = gaps.fold<int>(0, (sum, g) => sum + g.inMinutes);
      avgGap = Duration(minutes: totalMinutes ~/ gaps.length);
    }

    return {
      'count': entries.length,
      'first': sorted.first.timestamp,
      'last': sorted.last.timestamp,
      'avgGap': avgGap,
    };
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      if (hours > 0) {
        return '$days d $hours h';
      }
      return '$days d';
    } else if (d.inHours > 0) {
      return '${d.inHours} h ${d.inMinutes % 60} m';
    } else {
      return '${d.inMinutes} m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _matchingEntries;
    final stats = _getStats(entries);
    final weekdayData = _getWeekdayFrequency(entries);
    final timePeriodData = _getTimePeriodFrequency(entries);
    final weeklyTrend = _getWeeklyTrend(entries);
    final weeklyHeatmap = _getWeeklyHeatmap(entries);

    return Scaffold(
      appBar: AppBar(
        title: Text(entryWord),
      ),
      body: entries.isEmpty
          ? Center(child: Text('No entries found'))
          : ListView(
              padding: EdgeInsets.all(16),
              children: [
                // Stats summary
                _buildStatsCard(context, stats),
                SizedBox(height: 16),

                // Weekly radial heatmap
                if (entries.length > 1) ...[
                  _buildSectionTitle(context, 'Weekly Heatmap'),
                  SizedBox(height: 8),
                  Center(child: _buildWeeklyRadialChart(context, weeklyHeatmap)),
                  SizedBox(height: 24),
                ],

                // Weekday chart
                if (entries.length > 1) ...[
                  _buildSectionTitle(context, 'By Weekday'),
                  SizedBox(height: 8),
                  _buildBarChart(
                    data: weekdayData,
                    labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                    barColor: Colors.blue,
                  ),
                  SizedBox(height: 24),
                ],

                // Time of day chart
                if (entries.length > 1) ...[
                  _buildSectionTitle(context, 'By Time of Day'),
                  SizedBox(height: 8),
                  _buildBarChart(
                    data: timePeriodData,
                    labels: ['Morn', 'Mid', 'Aftn', 'Eve', 'Night'],
                    barColor: Colors.orange,
                  ),
                  SizedBox(height: 24),
                ],

                // Weekly trend chart
                if (weeklyTrend.length > 1) ...[
                  _buildSectionTitle(context, 'Weekly Trend'),
                  SizedBox(height: 8),
                  _buildTrendChart(context, weeklyTrend),
                  SizedBox(height: 24),
                ],

                // Trigger Analysis (only for @symptom entries)
                if (_isSymptom && entries.length >= 2) ...[
                  _buildSectionTitle(context, 'Potential Triggers (24h before)'),
                  SizedBox(height: 8),
                  _buildTriggerAnalysis(context, entries),
                  SizedBox(height: 24),
                ],

                // Timeline
                _buildSectionTitle(context, 'Timeline'),
                SizedBox(height: 8),
                _buildTimeline(context, entries),
              ],
            ),
    );
  }

  Widget _buildStatsCard(BuildContext context, Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(context, 'Total', '${stats['count']}'),
                if (stats['first'] != null)
                  _buildStatItem(
                    context,
                    'First',
                    DateTimeFormatter(stats['first']).date,
                  ),
                if (stats['last'] != null)
                  _buildStatItem(
                    context,
                    'Last',
                    DateTimeFormatter(stats['last']).date,
                  ),
              ],
            ),
            if (stats['avgGap'] != null) ...[
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 8),
              Text(
                'Average gap: ${_formatDuration(stats['avgGap'])}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _liftColor(double lift) {
    if (lift >= 3.0) return Colors.red;
    if (lift >= 2.0) return Colors.orange;
    if (lift >= 1.5) return Colors.amber.shade700;
    return Colors.grey;
  }

  Widget _buildTriggerAnalysis(BuildContext context, List<WordEntry> entries) {
    final triggers = _getTriggerAnalysis(entries);
    if (triggers.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Not enough data to identify triggers yet.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    // Only show entries with lift > 1 (more likely before symptom than normal)
    final significant = triggers.where((t) => (t['lift'] as double) > 1.0).toList();
    if (significant.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No unusual patterns found before this symptom.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    final maxLift = significant.first['lift'] as double;

    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: significant.take(10).map((t) {
            final lift = t['lift'] as double;
            final count = t['count'] as int;
            final word = t['word'] as String;
            final rate = t['rate'] as double;
            final baselineRate = t['baselineRate'] as double;
            final avgLead = t['avgLead'] as Duration;
            final pct = (rate * 100).round();
            final basePct = (baselineRate * 100).round();
            final color = _liftColor(lift);

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          word,
                          style: TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${lift.toStringAsFixed(1)}x',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (lift / maxLift).clamp(0.0, 1.0),
                      backgroundColor: Colors.grey[200],
                      color: color,
                      minHeight: 6,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Before $pct% of symptoms ($count/${entries.length})  ·  '
                    'Logged on $basePct% of days  ·  '
                    '~${_formatDuration(avgLead)} before',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  Widget _buildBarChart({
    required List<int> data,
    required List<String> labels,
    required Color barColor,
  }) {
    final maxY = data.reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY * 1.2 : 1,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${labels[group.x]}: ${rod.toY.toInt()}',
                  TextStyle(color: Colors.white, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) return SizedBox();
                  return Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      labels[index],
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  );
                },
                reservedSize: 24,
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: false),
          barGroups: List.generate(data.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data[index].toDouble(),
                  color: barColor,
                  width: 28,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTrendChart(
      BuildContext context, List<MapEntry<DateTime, int>> weeklyTrend) {
    if (weeklyTrend.isEmpty) return SizedBox();

    final maxY = weeklyTrend
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    final spots = <FlSpot>[];
    for (int i = 0; i < weeklyTrend.length; i++) {
      spots.add(FlSpot(i.toDouble(), weeklyTrend[i].value.toDouble()));
    }

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).clamp(1, double.infinity),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withValues(alpha: 0.2),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (weeklyTrend.length / 4).clamp(1, double.infinity),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= weeklyTrend.length) {
                    return SizedBox();
                  }
                  final date = weeklyTrend[index].key;
                  return Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '${date.month}/${date.day}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final index = spot.x.toInt();
                  if (index < 0 || index >= weeklyTrend.length) return null;
                  final date = weeklyTrend[index].key;
                  return LineTooltipItem(
                    'Week of ${date.month}/${date.day}: ${spot.y.toInt()}',
                    TextStyle(color: Colors.white, fontSize: 12),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.green,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: spots.length < 20),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, List<WordEntry> entries) {
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final dt = DateTimeFormatter(entry.timestamp);
        final isLast = index == entries.length - 1;

        // Calculate gap from previous entry (which is next in the sorted list)
        String? gapText;
        if (!isLast) {
          final nextEntry = entries[index + 1];
          final gap = entry.timestamp.difference(nextEntry.timestamp);
          gapText = _formatDuration(gap);
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line and dot
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: index == 0 ? Colors.blue : Colors.grey[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[300],
                        ),
                      ),
                  ],
                ),
              ),
              // Entry content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            dt.date,
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          SizedBox(width: 8),
                          Text(
                            dt.time,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Spacer(),
                          Text(
                            dt.daysAgo,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (gapText != null) ...[
                        SizedBox(height: 4),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '↑ $gapText',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildWeeklyRadialChart(BuildContext context, List<int> heatmapData) {
    final maxVal = heatmapData.reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        SizedBox(
          height: 280,
          width: 280,
          child: CustomPaint(
            painter: _WeeklyRadialPainter(
              data: heatmapData,
              maxValue: maxVal > 0 ? maxVal : 1,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Weekly',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    'Pattern',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem('Morn', Colors.amber),
            SizedBox(width: 12),
            _buildLegendItem('Aftn', Colors.orange),
            SizedBox(width: 12),
            _buildLegendItem('Eve', Colors.deepOrange),
            SizedBox(width: 12),
            _buildLegendItem('Night', Colors.indigo),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

class _WeeklyRadialPainter extends CustomPainter {
  final List<int> data;
  final int maxValue;
  final Color backgroundColor;

  static const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const periodColors = [
    Colors.amber,      // Morning
    Colors.orange,     // Afternoon
    Colors.deepOrange, // Evening
    Colors.indigo,     // Night
  ];

  _WeeklyRadialPainter({
    required this.data,
    required this.maxValue,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 20;
    final minRadius = maxRadius * 0.35;
    final labelRadius = maxRadius + 14;

    // Each slot is 360/28 degrees
    const slotAngle = 2 * math.pi / 28;
    const gapAngle = 0.02; // Small gap between bars
    const barAngle = slotAngle - gapAngle;

    // Start at top (-90 degrees = -π/2), going clockwise
    const startAngle = -math.pi / 2;

    for (int i = 0; i < 28; i++) {
      final dayIndex = i ~/ 4;
      final periodIndex = i % 4;
      final value = data[i];

      // Calculate bar height based on value
      final normalizedValue = value / maxValue;
      final barRadius = minRadius + (maxRadius - minRadius) * normalizedValue;

      // Calculate angles for this slot
      final slotStartAngle = startAngle + i * slotAngle;

      // Draw the bar
      final barPaint = Paint()
        ..color = periodColors[periodIndex].withValues(
          alpha: value > 0 ? 0.7 + 0.3 * normalizedValue : 0.15,
        )
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(
        center.dx + minRadius * math.cos(slotStartAngle),
        center.dy + minRadius * math.sin(slotStartAngle),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: minRadius),
        slotStartAngle,
        barAngle,
        false,
      );
      path.lineTo(
        center.dx + barRadius * math.cos(slotStartAngle + barAngle),
        center.dy + barRadius * math.sin(slotStartAngle + barAngle),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: barRadius),
        slotStartAngle + barAngle,
        -barAngle,
        false,
      );
      path.close();

      canvas.drawPath(path, barPaint);

      // Draw day labels at the start of each day (first period)
      if (periodIndex == 0) {
        final labelAngle = slotStartAngle + slotAngle * 2; // Center of day's slots
        final labelX = center.dx + labelRadius * math.cos(labelAngle);
        final labelY = center.dy + labelRadius * math.sin(labelAngle);

        final textPainter = TextPainter(
          text: TextSpan(
            text: dayLabels[dayIndex],
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2),
        );
      }
    }

    // Draw inner circle background
    final innerCirclePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, minRadius - 2, innerCirclePaint);
  }

  @override
  bool shouldRepaint(covariant _WeeklyRadialPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.maxValue != maxValue;
  }
}
