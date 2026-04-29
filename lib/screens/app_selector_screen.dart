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
  bool _showEnabledOnly = false;
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

  void _showThresholdPicker(BuildContext context, SettingsProvider settings, String packageName, String appName) {
    final globalThreshold = settings.notificationThreshold;
    final customThreshold = settings.getAppThreshold(packageName);

    showDialog(
      context: context,
      builder: (context) {
        return _ThresholdPickerDialog(
          appName: appName,
          globalThreshold: globalThreshold,
          customThreshold: customThreshold,
          onSave: (value) {
            settings.setAppThreshold(packageName, value);
          },
        );
      },
    );
  }

  void _showCooldownPicker(BuildContext context, SettingsProvider settings, String packageName, String appName) {
    final globalCooldown = settings.summaryCooldownMs;
    final customCooldown = settings.getAppCooldown(packageName);

    showDialog(
      context: context,
      builder: (context) {
        return _CooldownPickerDialog(
          appName: appName,
          globalCooldown: globalCooldown,
          customCooldown: customCooldown,
          onSave: (value) {
            settings.setAppCooldown(packageName, value);
          },
        );
      },
    );
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
    List<Map<String, String>> result = _apps;
    if (_showEnabledOnly) {
      final settings = context.read<SettingsProvider>();
      result = result.where((a) => settings.enabledApps.contains(a['packageName'])).toList();
    }
    if (_search.isEmpty) return result;
    final q = _search.toLowerCase();
    return result.where((a) =>
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

          // ── Filter chips ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Enabled only',
                      style: TextStyle(
                          color: _showEnabledOnly ? Colors.white : Colors.white54,
                          fontSize: 12)),
                  selected: _showEnabledOnly,
                  onSelected: (v) => setState(() => _showEnabledOnly = v),
                  selectedColor: const Color(0xFF4A7A56),
                  backgroundColor: const Color(0xFF2A2A2A),
                  checkmarkColor: Colors.white,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                const SizedBox(width: 8),
                if (selected.isNotEmpty)
                  ActionChip(
                    label: const Text('Clear list',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    onPressed: () => settings.setEnabledApps({}),
                    backgroundColor: const Color(0xFF2A2A2A),
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
              ],
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
                                      // Threshold picker button (only for selected apps)
                                      if (isSelected)
                                        IconButton(
                                          icon: Icon(
                                            Icons.filter_list,
                                            color: settings.getAppThreshold(pkg) != null
                                                ? const Color(0xFF6B9E78)
                                                : Colors.white38,
                                            size: 20,
                                          ),
                                          tooltip: 'Set threshold',
                                          onPressed: () => _showThresholdPicker(context, settings, pkg, name),
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
                                      // Cooldown picker button (only for selected apps)
                                      if (isSelected)
                                        IconButton(
                                          icon: Icon(
                                            Icons.timer,
                                            color: settings.getAppCooldown(pkg) > 0
                                                ? const Color(0xFF6B9E78)
                                                : Colors.white38,
                                            size: 20,
                                          ),
                                          tooltip: 'Set cooldown',
                                          onPressed: () => _showCooldownPicker(context, settings, pkg, name),
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

class _ThresholdPickerDialog extends StatefulWidget {
  final String appName;
  final int globalThreshold;
  final int? customThreshold;
  final void Function(int?) onSave;

  const _ThresholdPickerDialog({
    required this.appName,
    required this.globalThreshold,
    required this.customThreshold,
    required this.onSave,
  });

  @override
  State<_ThresholdPickerDialog> createState() => _ThresholdPickerDialogState();
}

class _ThresholdPickerDialogState extends State<_ThresholdPickerDialog> {
  late bool _useCustom;
  late double _value;

  @override
  void initState() {
    super.initState();
    _useCustom = widget.customThreshold != null;
    _value = (widget.customThreshold ?? widget.globalThreshold).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Threshold for ${widget.appName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use custom threshold'),
              subtitle: Text(
                _useCustom
                    ? 'Override global setting for this app'
                    : 'Use global threshold (${widget.globalThreshold})',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              value: _useCustom,
              onChanged: (v) => setState(() => _useCustom = v),
            ),
            const SizedBox(height: 8),
            if (_useCustom) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Summarise after ${_value.round()} notification${_value.round() == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF6B9E78),
                  inactiveTrackColor: const Color(0xFF3A3A3A),
                  thumbColor: const Color(0xFF6B9E78),
                  overlayColor: const Color(0xFF6B9E78).withOpacity(0.2),
                  trackHeight: 3,
                ),
                child: Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: _value,
                  onChanged: (v) => setState(() => _value = v),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  Text('10', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Global: ${widget.globalThreshold} notification${widget.globalThreshold == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_useCustom ? _value.round() : null);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CooldownPickerDialog extends StatefulWidget {
  final String appName;
  final int globalCooldown;
  final int customCooldown;
  final void Function(int) onSave;

  const _CooldownPickerDialog({
    required this.appName,
    required this.globalCooldown,
    required this.customCooldown,
    required this.onSave,
  });

  @override
  State<_CooldownPickerDialog> createState() => _CooldownPickerDialogState();
}

class _CooldownPickerDialogState extends State<_CooldownPickerDialog> {
  late bool _useCustom;
  late double _value;

  @override
  void initState() {
    super.initState();
    _useCustom = widget.customCooldown > 0;
    _value = (_useCustom ? widget.customCooldown : widget.globalCooldown).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cooldown for ${widget.appName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use custom cooldown'),
              subtitle: Text(
                _useCustom
                    ? 'Override global setting for this app'
                    : 'Use global cooldown (${widget.globalCooldown ~/ 1000}s)',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              value: _useCustom,
              onChanged: (v) => setState(() => _useCustom = v),
            ),
            const SizedBox(height: 8),
            if (_useCustom) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Wait ${_value.round() ~/ 1000}s before re-summarising',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF6B9E78),
                  inactiveTrackColor: const Color(0xFF3A3A3A),
                  thumbColor: const Color(0xFF6B9E78),
                  overlayColor: const Color(0xFF6B9E78).withOpacity(0.2),
                  trackHeight: 3,
                ),
                child: Slider(
                  min: 5000,
                  max: 120000,
                  divisions: 23,
                  value: _value,
                  onChanged: (v) => setState(() => _value = v),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5s', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  Text('120s', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Global: ${widget.globalCooldown ~/ 1000}s',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_useCustom ? _value.round() : 0);
            Navigator.pop(context);
          },
          child: const Text('Save'),
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
