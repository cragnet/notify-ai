import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/permissions_service.dart';

class AppSelectorScreen extends StatefulWidget {
  const AppSelectorScreen({super.key});

  @override
  State<AppSelectorScreen> createState() => _AppSelectorScreenState();
}

class _AppSelectorScreenState extends State<AppSelectorScreen> {
  List<Map<String, String>> _apps = [];
  bool _loading = true;
  String _error = '';
  String _search = '';
  final _searchCtrl = TextEditingController();

  // Icon cache — shared across all list items, persists across rebuilds
  static final Map<String, Future<Uint8List?>> _iconCache = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final apps = await PermissionsService.getInstalledApps();
      if (mounted) {
        setState(() {
          _apps = apps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showColorPicker(BuildContext context, SettingsProvider settings, String packageName, String appName) {
    final currentColor = settings.getNotificationColor(packageName);

    // Predefined colors
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
      Colors.grey,
      Colors.black,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Notification color for $appName'),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Clear color option
              _ColorOption(
                color: null,
                isSelected: currentColor == null,
                onTap: () {
                  settings.setNotificationColor(packageName, null);
                  Navigator.pop(context);
                },
                label: 'Default',
              ),
              ...colors.map((color) => _ColorOption(
                color: color,
                isSelected: currentColor == color.value,
                onTap: () {
                  settings.setNotificationColor(packageName, color.value);
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> get _filtered {
    if (_search.isEmpty) return _apps;
    final q = _search.toLowerCase();
    return _apps.where((a) =>
        (a['appName'] ?? '').toLowerCase().contains(q) ||
        (a['packageName'] ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final selected = settings.enabledApps;

    // Build readable selection summary
    final selectedNames = selected.map((pkg) {
      final match = _apps.firstWhere(
        (a) => a['packageName'] == pkg,
        orElse: () => {'appName': pkg.split('.').last},
      );
      return match['appName'] ?? pkg;
    }).toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select apps to monitor'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => settings.setEnabledApps({}),
              child: const Text('Clear all',
                  style: TextStyle(color: Color(0xFF6B9E78))),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scan,
            tooltip: 'Rescan apps',
          ),
        ],
      ),
      body: Column(
        children: [

          // ── Selection summary banner ─────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected.isEmpty
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFF2A3A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected.isEmpty
                    ? Colors.white10
                    : const Color(0xFF4A7A56),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected.isEmpty ? Icons.touch_app_outlined : Icons.check_circle,
                  color: selected.isEmpty
                      ? Colors.white30
                      : const Color(0xFF6B9E78),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: selected.isEmpty
                      ? const Text(
                          'Tap an app below to start monitoring it',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selected.length} app${selected.length == 1 ? '' : 's'} selected',
                              style: const TextStyle(
                                color: Color(0xFF6B9E78),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedNames.join(' · '),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search ${_apps.length} installed apps…',
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // ── App list ─────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6B9E78)),
                        SizedBox(height: 16),
                        Text('Scanning installed apps…',
                            style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  )
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.white38, size: 48),
                              const SizedBox(height: 12),
                              const Text('Could not load apps',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16)),
                              const SizedBox(height: 8),
                              Text(_error,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _scan,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              _search.isNotEmpty
                                  ? 'No apps match "$_search"'
                                  : 'No apps found',
                              style: const TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final app = _filtered[index];
                              final pkg = app['packageName'] ?? '';
                              final name = app['appName'] ?? pkg;
                              final isSelected = selected.contains(pkg);

                              final notificationColor = settings.getNotificationColor(pkg);

                              return InkWell(
                                onTap: () => settings.toggleApp(pkg),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  child: Row(
                                    children: [
                                      _AppIcon(
                                        packageName: pkg,
                                        appName: name,
                                        iconFuture: _iconCache.putIfAbsent(
                                          pkg,
                                          () => PermissionsService.getAppIcon(pkg),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name,
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500)),
                                            Text(pkg,
                                                style: const TextStyle(
                                                    color: Colors.white24,
                                                    fontSize: 11),
                                                overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      // Color picker button (only for selected apps)
                                      if (isSelected)
                                        IconButton(
                                          icon: Icon(
                                            Icons.color_lens,
                                            color: notificationColor != null
                                                ? Color(notificationColor)
                                                : Colors.white38,
                                            size: 20,
                                          ),
                                          tooltip: 'Set notification color',
                                          onPressed: () => _showColorPicker(context, settings, pkg, name),
                                        ),
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => settings.toggleApp(pkg),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;
  final String? label;

  const _ColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color ?? Colors.grey[800],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: color == null
                ? const Icon(Icons.format_color_reset, color: Colors.white54)
                : isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String packageName;
  final String appName;
  final Future<Uint8List?> iconFuture;

  const _AppIcon({
    required this.packageName,
    required this.appName,
    required this.iconFuture,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: iconFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.done &&
            snap.hasData && snap.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(snap.data!, width: 42, height: 42, fit: BoxFit.cover),
          );
        }
        // Fallback: coloured letter avatar while loading or if icon unavailable
        final letter = appName.isNotEmpty ? appName[0].toUpperCase() : '?';
        const colors = [
          Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
          Color(0xFFFF5722), Color(0xFF00BCD4), Color(0xFFFF9800),
          Color(0xFF607D8B), Color(0xFFE91E63), Color(0xFF795548),
          Color(0xFF3F51B5), Color(0xFF009688), Color(0xFFCDDC39),
        ];
        final color = colors[packageName.hashCode.abs() % colors.length];
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(letter,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
          ),
        );
      },
    );
  }
}
