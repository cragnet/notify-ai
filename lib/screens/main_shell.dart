import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/permissions_service.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'log_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _listenerMissing = false;

  static const _screens = [
    HistoryScreen(),
    StatsScreen(),
    LogScreen(),
    HomeScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreIndex();
    _checkListener();
  }

  Future<void> _restoreIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('main_tab_index') ?? 0;
    if (mounted) setState(() => _index = saved);
  }

  Future<void> _saveIndex(int i) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('main_tab_index', i);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkListener();
  }

  Future<void> _checkListener() async {
    final ok = await PermissionsService.isNotificationListenerEnabled();
    if (mounted) setState(() => _listenerMissing = !ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_listenerMissing)
            Material(
              color: Colors.red.shade900,
              child: InkWell(
                onTap: () async {
                  await PermissionsService.openNotificationListenerSettings();
                  await _checkListener();
                },
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 40, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notification access is off — tap to fix',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white54, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        indicatorColor: const Color(0xFF2A3A2E),
        selectedIndex: _index,
        onDestinationSelected: (i) { setState(() => _index = i); _saveIndex(i); },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications, color: Color(0xFF6B9E78)),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: Color(0xFF6B9E78)),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal, color: Color(0xFF6B9E78)),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF6B9E78)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
