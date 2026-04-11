import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/permissions_service.dart';

class AppSelectorScreen extends StatefulWidget {
  const AppSelectorScreen({super.key});

  @override
  State<AppSelectorScreen> createState() => _AppSelectorScreenState();
}

class _AppSelectorScreenState extends State<AppSelectorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, String>> _all = [];
  bool _loading = true;
  String _search = '';

  static const _chatPackages = {
    'com.whatsapp', 'org.telegram.messenger', 'org.telegram.plus',
    'com.facebook.orca', 'com.facebook.lite', 'com.instagram.android',
    'com.snapchat.android', 'com.discord', 'com.viber.voip',
    'com.skype.raider', 'com.microsoft.teams', 'com.slack',
    'org.thoughtcrime.securesms', 'com.google.android.apps.messaging',
    'com.samsung.android.messaging', 'com.android.mms',
    'com.twitter.android', 'com.linkedin.android', 'com.tiktok',
    'com.wire', 'com.groupme.android', 'jp.naver.line.android',
  };

  static const _emailPackages = {
    'com.google.android.gm', 'com.microsoft.office.outlook',
    'com.yahoo.mobile.client.android.mail', 'me.bluemail.mail',
    'net.thunderbird.android', 'com.aqua.mail', 'com.fastmail.app',
    'com.protonmail.protonmail', 'ch.protonmail.android',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadApps();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await PermissionsService.getInstalledApps();
    if (mounted) setState(() { _all = apps; _loading = false; });
  }

  bool _isChat(String pkg) => _chatPackages.any((c) => pkg.startsWith(c));
  bool _isEmail(String pkg) => _emailPackages.any((e) => pkg.startsWith(e));

  List<Map<String, String>> _filtered(int tab) {
    List<Map<String, String>> list;
    switch (tab) {
      case 0: list = _all.where((a) => _isChat(a['packageName']!)).toList(); break;
      case 1: list = _all.where((a) => _isEmail(a['packageName']!)).toList(); break;
      default: list = _all.where((a) => !_isChat(a['packageName']!) && !_isEmail(a['packageName']!)).toList();
    }
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((a) =>
        (a['appName'] ?? '').toLowerCase().contains(q) ||
        (a['packageName'] ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final selected = settings.enabledApps;

    // Build selection summary label
    String summaryText;
    if (selected.isEmpty) {
      summaryText = 'No apps selected';
    } else {
      final names = selected.map((pkg) {
        final match = _all.firstWhere(
            (a) => a['packageName'] == pkg,
            orElse: () => {'appName': pkg.split('.').last});
        return match['appName'] ?? pkg;
      }).toList()..sort();
      summaryText = names.join(', ');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Per-app settings'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => settings.setEnabledApps({}),
              child: const Text('Clear all',
                  style: TextStyle(color: Color(0xFF6B9E78))),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Selection summary ─────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected.isEmpty
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFF2A3A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  selected.isEmpty ? Icons.info_outline : Icons.check_circle,
                  color: selected.isEmpty ? Colors.white30 : const Color(0xFF6B9E78),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? 'Select apps to monitor below'
                        : '${selected.length} selected: $summaryText',
                    style: TextStyle(
                      color: selected.isEmpty ? Colors.white38 : Colors.white70,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search apps…',
                prefixIcon: Icon(Icons.search, color: Colors.white38, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabs,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: const Color(0xFF4A7A56),
                borderRadius: BorderRadius.circular(10),
              ),
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.chat_bubble_outline, size: 15), SizedBox(width: 4), Text('Chats')])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.email_outlined, size: 15), SizedBox(width: 4), Text('Email')])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.apps, size: 15), SizedBox(width: 4), Text('All')])),
              ],
            ),
          ),

          // ── App list ──────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B9E78)))
                : TabBarView(
                    controller: _tabs,
                    children: List.generate(3, (i) {
                      final apps = _filtered(i);
                      if (apps.isEmpty) {
                        return Center(
                          child: Text(
                            _search.isNotEmpty ? 'No apps match "$_search"' : 'No apps in this category',
                            style: const TextStyle(color: Colors.white38),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: apps.length,
                        itemBuilder: (ctx, idx) {
                          final app = apps[idx];
                          final pkg = app['packageName']!;
                          final name = app['appName']!;
                          final isSelected = selected.contains(pkg);
                          return ListTile(
                            leading: _AppAvatar(pkg),
                            title: Text(name),
                            subtitle: Text(pkg,
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => settings.toggleApp(pkg),
                            ),
                            onTap: () => settings.toggleApp(pkg),
                          );
                        },
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppAvatar extends StatelessWidget {
  final String packageName;
  const _AppAvatar(this.packageName);

  @override
  Widget build(BuildContext context) {
    final letter = packageName.split('.').lastWhere(
        (s) => s.isNotEmpty, orElse: () => 'A')[0].toUpperCase();
    final color = _color(packageName);
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(letter,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
    );
  }

  Color _color(String pkg) {
    const c = [
      Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF5722), Color(0xFF00BCD4), Color(0xFFFF9800),
      Color(0xFF607D8B), Color(0xFFE91E63), Color(0xFF795548),
    ];
    return c[pkg.hashCode.abs() % c.length];
  }
}
