import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/permissions_service.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  bool _notificationListener = false;
  bool _postNotifications = false;
  bool _usageStats = false;
  bool _batteryOptimization = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    final nl = await PermissionsService.isNotificationListenerEnabled();
    final pn = await PermissionsService.isPostNotificationsGranted();
    final us = await PermissionsService.isUsageStatsPermissionGranted();
    final bo = await PermissionsService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _notificationListener = nl;
        _postNotifications = pn;
        _usageStats = us;
        _batteryOptimization = bo;
      });
    }
  }

  // Notification listener, post notifications, and battery optimisation are mandatory
  bool get _canContinue => _notificationListener && _postNotifications && _batteryOptimization;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth > 600 ? constraints.maxWidth * 0.15 : 24,
                vertical: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  const Text('Setup',
                      style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Grant the permissions below to get started.\nConfigure your AI provider in Settings afterwards.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  _PermissionRow(
                    title: 'Notification access',
                    subtitle: 'Required — allows Notify AI to read incoming notifications',
                    granted: _notificationListener,
                    required: true,
                    onTap: () => PermissionsService.openNotificationListenerSettings(),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'Allow notifications',
                    subtitle: 'Required — allows Notify AI to post AI summaries',
                    granted: _postNotifications,
                    required: true,
                    onTap: () async {
                      await PermissionsService.requestPostNotifications();
                      await _checkAll();
                    },
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'App usage access',
                    subtitle: 'Recommended — used for statistics',
                    granted: _usageStats,
                    required: false,
                    onTap: () => PermissionsService.openUsageStatsSettings(),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'Disable battery optimisation',
                    subtitle: 'Required — keeps the service alive in background',
                    granted: _batteryOptimization,
                    required: true,
                    onTap: () => PermissionsService.requestIgnoreBatteryOptimization(),
                  ),

                  const SizedBox(height: 48),

                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _canContinue
                              ? () async {
                                  // completeSetup() sets setupComplete=true and calls
                                  // notifyListeners() — _AppEntry reacts and swaps to
                                  // MainShell automatically. No Navigator push needed.
                                  await context.read<SettingsProvider>().completeSetup();
                                }
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _canContinue
                                  ? const Color(0xFF6B9E78)
                                  : const Color(0xFF2A2A2A),
                            ),
                            child: const Icon(Icons.arrow_forward, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _canContinue
                              ? 'Tap to continue'
                              : 'Grant required permissions above to continue',
                          style: TextStyle(
                            color: _canContinue ? Colors.white60 : Colors.white30,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final bool required;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.required,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: granted ? null : onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              granted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: granted
                  ? const Color(0xFF6B9E78)
                  : (required ? Colors.white54 : Colors.white24),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: granted ? Colors.white : Colors.white70)),
                    ),
                    if (required && !granted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B9E78).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Required',
                            style: TextStyle(
                                color: Color(0xFF6B9E78),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.white38)),
              ],
            ),
          ),
          if (!granted)
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
        ],
      ),
    );
  }
}
