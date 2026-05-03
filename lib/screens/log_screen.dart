import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'home_screen.dart';

class LogEntry {
  final String timestamp;
  final String level;
  final String message;
  const LogEntry({required this.timestamp, required this.level, required this.message});
  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
      timestamp: j['timestamp'] as String? ?? '',
      level: j['level'] as String? ?? 'info',
      message: j['message'] as String? ?? '');
  Map<String, dynamic> toJson() =>
      {'timestamp': timestamp, 'level': level, 'message': message};
}

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with WidgetsBindingObserver {
  List<LogEntry> _entries = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    // Reload from disk — the native service writes directly to SharedPreferences
    // and Flutter's in-memory cache won't see updates without reload()
    await prefs.reload();
    final raw = prefs.getString('service_log') ?? '[]';
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() { _entries = list.reversed.toList(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }



  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Clear log?'),
        content: const Text('This will permanently delete all log entries.',
            style: TextStyle(color: Colors.white70)),
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
      await prefs.setString('service_log', '[]');
      setState(() => _entries = []);
    }
  }

  List<LogEntry> get _filtered =>
      _filter == 'all' ? _entries : _entries.where((e) => e.level == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: _clear),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6B9E78),
        onRefresh: () => _load(showSpinner: true),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _Chip(label: 'All', value: 'all', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _Chip(label: 'Info', value: 'info', current: _filter,
                      color: Colors.white54, onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _Chip(label: 'Success', value: 'success', current: _filter,
                      color: const Color(0xFF6B9E78), onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _Chip(label: 'Warning', value: 'warn', current: _filter,
                      color: const Color(0xFFE8A838), onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _Chip(label: 'Error', value: 'error', current: _filter,
                      color: Colors.redAccent, onTap: (v) => setState(() => _filter = v)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Text('${_filtered.length} entries',
                      style: const TextStyle(color: Colors.white30, fontSize: 12)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      final text = _filtered.map((e) =>
                          '[${e.timestamp}] [${e.level.toUpperCase()}] ${e.message}').join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Log copied to clipboard'),
                          backgroundColor: Color(0xFF4A7A56)));
                    },
                    child: const Text('Copy all',
                        style: TextStyle(color: Color(0xFF6B9E78), fontSize: 12)),
                  ),
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
                                    const Icon(Icons.receipt_long_outlined,
                                        size: 48, color: Colors.white24),
                                    const SizedBox(height: 12),
                                    const Text('No log entries yet',
                                        style: TextStyle(color: Colors.white38, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    const Text(
                                        'Activity appears here once the service intercepts notifications.\nMake sure apps are selected and notification access is granted.',
                                        style: TextStyle(color: Colors.white24, fontSize: 12),
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _LogRow(entry: _filtered[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  Color get _color {
    switch (entry.level) {
      case 'success': return const Color(0xFF6B9E78);
      case 'warn': return const Color(0xFFE8A838);
      case 'error': return Colors.redAccent;
      default: return Colors.white54;
    }
  }

  IconData get _icon {
    switch (entry.level) {
      case 'success': return Icons.check_circle_outline;
      case 'warn': return Icons.warning_amber_outlined;
      case 'error': return Icons.error_outline;
      default: return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: _color, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.message,
                      style: TextStyle(color: _color, fontSize: 13, height: 1.3)),
                  Text(entry.timestamp,
                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final Color color;
  final void Function(String) onTap;
  const _Chip({required this.label, required this.value, required this.current,
      this.color = Colors.white70, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.white12),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : Colors.white38,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
