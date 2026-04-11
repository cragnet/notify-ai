import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stat_entry.dart';
import 'dart:convert';

class StatsProvider extends ChangeNotifier {
  List<StatEntry> _entries = [];
  bool loading = false;

  List<StatEntry> get entries => _entries;

  Future<void> load() async {
    loading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final allKeysJson = prefs.getString('stats_all_keys') ?? '[]';
    final allKeys = (jsonDecode(allKeysJson) as List).cast<String>();

    final entries = <StatEntry>[];
    for (final key in allKeys) {
      // key format: flutter.stats_<packageName>_<yyyy-MM-dd>
      final raw = prefs.getString(key.replaceFirst('flutter.', ''));
      // Also try without prefix
      final raw2 = prefs.getString(key);
      final jsonStr = raw ?? raw2;
      if (jsonStr == null) continue;

      try {
        final parts = key.replaceFirst('flutter.stats_', '').replaceFirst('stats_', '');
        // Last 10 chars = date
        if (parts.length < 11) continue;
        final date = parts.substring(parts.length - 10);
        final packageName = parts.substring(0, parts.length - 11);
        if (packageName.isEmpty) continue;

        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        entries.add(StatEntry(
          packageName: packageName,
          appName: packageName.split('.').last.replaceFirst(
            packageName.split('.').last[0],
            packageName.split('.').last[0].toUpperCase(),
          ),
          date: date,
          intercepted: obj['intercepted'] as int? ?? 0,
          summarised: obj['summarised'] as int? ?? 0,
        ));
      } catch (_) {}
    }

    _entries = entries;
    loading = false;
    notifyListeners();
  }

  // Returns per-app totals for a date range
  List<AppStats> appTotals(DateTime from, DateTime to) {
    final map = <String, AppStats>{};
    for (final e in _entries) {
      try {
        final d = DateTime.parse(e.date);
        if (d.isBefore(from) || d.isAfter(to)) continue;
        final stats = map.putIfAbsent(
          e.packageName,
          () => AppStats(packageName: e.packageName, appName: e.appName),
        );
        stats.intercepted += e.intercepted;
        stats.summarised += e.summarised;
      } catch (_) {}
    }
    final list = map.values.toList();
    list.sort((a, b) => b.intercepted.compareTo(a.intercepted));
    return list;
  }

  // Returns daily totals for a date range (for chart)
  List<DailyTotal> dailyTotals(DateTime from, DateTime to) {
    final map = <String, DailyTotal>{};
    for (final e in _entries) {
      try {
        final d = DateTime.parse(e.date);
        if (d.isBefore(from) || d.isAfter(to)) continue;
        final existing = map[e.date];
        if (existing == null) {
          map[e.date] = DailyTotal(
            date: e.date,
            intercepted: e.intercepted,
            summarised: e.summarised,
          );
        } else {
          map[e.date] = DailyTotal(
            date: e.date,
            intercepted: existing.intercepted + e.intercepted,
            summarised: existing.summarised + e.summarised,
          );
        }
      } catch (_) {}
    }
    final list = map.values.toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }
}
