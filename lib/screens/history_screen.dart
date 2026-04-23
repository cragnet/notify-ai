import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'home_screen.dart';

class HistoryEntry {
  final String packageName;
  final String appName;
  final String title;
  final String message;
  final String timestamp;
  final bool hadImage;

  const HistoryEntry({
    required this.packageName, required this.appName,
    required this.title, required this.message,
    required this.timestamp, this.hadImage = false,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
      packageName: j['packageName'] as String? ?? '',
      appName: j['appName'] as String? ?? '',
      title: j['title'] as String? ?? '',
      message: j['message'] as String? ?? '',
      timestamp: j['timestamp'] as String? ?? '',
      hadImage: j['hadImage'] as bool? ?? false);
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with WidgetsBindingObserver {
  List<HistoryEntry> _entries = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    // Native service writes 'notification_history' directly (no flutter. prefix)
    // Flutter prefs reads it as 'notification_history' which maps to
    // 'flutter.notification_history' in the XML — we need to match the service
    final raw = prefs.getString('notification_history') ?? '[]';
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Clear history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notification_history', '[]');
      setState(() => _entries = []);
    }
  }

  List<HistoryEntry> get _filtered {
    if (_search.isEmpty) return _entries;
    final q = _search.toLowerCase();
    return _entries.where((e) =>
        e.appName.toLowerCase().contains(q) ||
        e.title.toLowerCase().contains(q) ||
        e.message.toLowerCase().contains(q)).toList();
  }

  Map<String, List<HistoryEntry>> get _grouped {
    final map = <String, List<HistoryEntry>>{};
    for (final e in _filtered) {
      try {
        final dt = DateTime.parse(e.timestamp);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final entryDate = DateTime(dt.year, dt.month, dt.day);
        String label;
        if (entryDate == today) label = 'Today';
        else if (entryDate == yesterday) label = 'Yesterday';
        else label = DateFormat('EEEE d MMMM').format(dt);
        map.putIfAbsent(label, () => []).add(e);
      } catch (_) {
        map.putIfAbsent('Unknown', () => []).add(e);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final dateKeys = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
          if (_entries.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white54),
                onPressed: _clear),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6B9E78),
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search history…',
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Text('${_filtered.length} notifications',
                      style: const TextStyle(color: Colors.white30, fontSize: 12)),
                  const Spacer(),
                  const Text('Last 30 days',
                      style: TextStyle(color: Colors.white24, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B9E78)))
                  : _filtered.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.notifications_none, size: 48, color: Colors.white24),
                                    const SizedBox(height: 12),
                                    Text(_search.isNotEmpty ? 'No results for "$_search"' : 'No history yet',
                                        style: const TextStyle(color: Colors.white38, fontSize: 16)),
                                    if (_search.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(32, 4, 32, 0),
                                        child: Text(
                                          'Intercepted notifications will appear here.\nCheck the Log tab if nothing is appearing.',
                                          style: TextStyle(color: Colors.white24, fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: dateKeys.length,
                          itemBuilder: (ctx, i) {
                            final label = dateKeys[i];
                            final dayEntries = grouped[label]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                                  child: Text(label,
                                      style: const TextStyle(
                                          color: Color(0xFF6B9E78), fontSize: 13,
                                          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF1E1E1E),
                                      borderRadius: BorderRadius.circular(16)),
                                  clipBehavior: Clip.hardEdge,
                                  child: Column(
                                    children: dayEntries.asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final e = entry.value;
                                      return Column(children: [
                                        _Tile(entry: e),
                                        if (idx < dayEntries.length - 1)
                                          const Divider(color: Colors.white10, height: 1),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final HistoryEntry entry;
  const _Tile({required this.entry});

  String _time() {
    try { return DateFormat('HH:mm').format(DateTime.parse(entry.timestamp).toLocal()); }
    catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(entry.packageName, entry.appName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(entry.appName,
                        style: const TextStyle(color: Color(0xFF6B9E78),
                            fontSize: 11, fontWeight: FontWeight.w600))),
                    Text(_time(),
                        style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  ]),
                  const SizedBox(height: 2),
                  Text(entry.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(entry.message,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (entry.hadImage) ...[
                    const SizedBox(height: 4),
                    const Row(children: [
                      Icon(Icons.image_outlined, color: Colors.white30, size: 12),
                      SizedBox(width: 4),
                      Text('Contained image',
                          style: TextStyle(color: Colors.white30, fontSize: 11)),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  final String pkg, name;
  const _Avatar(this.pkg, this.name);
  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    const colors = [Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF5722), Color(0xFF00BCD4), Color(0xFFFF9800), Color(0xFF607D8B),
      Color(0xFFE91E63), Color(0xFF795548), Color(0xFF3F51B5), Color(0xFF009688)];
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
          color: colors[pkg.hashCode.abs() % colors.length],
          borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(letter,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
    );
  }
}
