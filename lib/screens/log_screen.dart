import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LogEntry {
  final String timestamp;
  final String level; // info, success, warn, error
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        timestamp: j['timestamp'] as String,
        level: j['level'] as String? ?? 'info',
        message: j['message'] as String,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'level': level,
        'message': message,
      };
}

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<LogEntry> _entries = [];
  bool _loading = true;
  final _scrollCtrl = ScrollController();
  String _filter = 'all'; // all, info, success, warn, error

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
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

  List<LogEntry> get _filtered {
    if (_filter == 'all') return _entries;
    return _entries.where((e) => e.level == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Log'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _FilterChip(label: 'All', value: 'all', current: _filter,
                    onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Info', value: 'info', current: _filter,
                    color: Colors.white54, onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Success', value: 'success', current: _filter,
                    color: const Color(0xFF6B9E78), onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Warning', value: 'warn', current: _filter,
                    color: const Color(0xFFE8A838), onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Error', value: 'error', current: _filter,
                    color: Colors.redAccent, onTap: (v) => setState(() => _filter = v)),
              ],
            ),
          ),

          // Count
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Log copied to clipboard'),
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            const Text('No log entries yet',
                                style: TextStyle(color: Colors.white38, fontSize: 16)),
                            const SizedBox(height: 4),
                            const Text('Activity will appear here once the service starts intercepting notifications',
                                style: TextStyle(color: Colors.white24, fontSize: 12),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final entry = _filtered[i];
                          return _LogRow(entry: entry);
                        },
                      ),
          ),
        ],
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
  Widget build(BuildContext context) {
    return Padding(
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
}

class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final Color color;
  final void Function(String) onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    this.color = Colors.white70,
    required this.onTap,
  });

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
