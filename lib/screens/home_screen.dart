import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../models/provider_config.dart';
import '../services/permissions_service.dart';
import 'provider_settings_screen.dart';
import 'app_selector_screen.dart';
import 'import_export_screen.dart';
import 'about_screen.dart';
import 'prompt_settings_screen.dart';
import 'digest_settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final provider = providerById(settings.aiProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notify AI')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 600;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? constraints.maxWidth * 0.12 : 16,
              vertical: 8,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _leftColumn(context, settings, provider)),
                      const SizedBox(width: 16),
                      Expanded(child: _rightColumn(context, settings)),
                    ],
                  )
                : Column(
                    children: [
                      ..._leftColumn(context, settings, provider).children,
                      ..._rightColumn(context, settings).children,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Column _leftColumn(BuildContext context, SettingsProvider settings, ProviderConfig? provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Master toggle
        _Card(
          child: SwitchListTile(
            title: const Text('Summarisation enabled',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              settings.serviceEnabled ? 'Running — notifications are being monitored' : 'Paused',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            value: settings.serviceEnabled,
            onChanged: settings.setServiceEnabled,
          ),
        ),
        const SizedBox(height: 8),
        _Label('Setup'),
        _Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome, color: Color(0xFF6B9E78)),
            title: const Text('AI Provider & Model'),
            subtitle: Text(
              provider?.displayName ?? settings.aiProvider,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProviderSettingsScreen())),
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_active, color: Color(0xFF6B9E78)),
            title: const Text('Restart notification listener'),
            subtitle: const Text(
              'Tap if summaries stop appearing after force-stop or battery optimisation',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: const Icon(Icons.refresh, color: Colors.white38),
            onTap: () async {
              final ok = await PermissionsService.restartNotificationListener();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Notification listener restarted'
                      : 'Could not restart listener — toggle it manually in system settings'),
                  backgroundColor: ok ? const Color(0xFF6B9E78) : Colors.redAccent,
                ));
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        _Label('Apps'),
        _Card(
          child: ListTile(
            leading: const Icon(Icons.grid_view_outlined, color: Colors.white54),
            title: const Text('Per-app settings'),
            subtitle: Text(
              settings.enabledApps.isEmpty
                  ? 'No apps selected — tap to choose'
                  : '${settings.enabledApps.length} app${settings.enabledApps.length == 1 ? '' : 's'} selected',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AppSelectorScreen())),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Column _rightColumn(BuildContext context, SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Appearance'),
        _Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: Colors.white54),
                title: const Text('Theme'),
                subtitle: Text(
                  settings.themeMode == 0 ? 'Dark' : settings.themeMode == 1 ? 'Light' : 'System default',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                trailing: SizedBox(
                  width: 220,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Dark')),
                      ButtonSegment(value: 1, label: Text('Light')),
                      ButtonSegment(value: 2, label: Text('System')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                    style: ButtonStyle(
                      foregroundColor: MaterialStateProperty.resolveWith((states) =>
                          states.contains(MaterialState.selected) ? Colors.white : Colors.white54),
                      backgroundColor: MaterialStateProperty.resolveWith((states) =>
                          states.contains(MaterialState.selected) ? const Color(0xFF6B9E78) : Colors.transparent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Label('Digest summaries'),
        _Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.alarm, color: Colors.white54),
                title: const Text('Scheduled digest summaries'),
                subtitle: Text(
                  settings.digestEnabled
                      ? '${settings.digestScheduleType == 'fixed_times' ? 'Fixed times' : settings.digestScheduleType == 'interval' ? 'Every ${settings.digestIntervalMinutes} min' : settings.digestScheduleType == 'daily' ? 'Daily at ${settings.digestDailyTime}' : 'Weekly on ${['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][settings.digestWeeklyDay]} ${settings.digestWeeklyTime}'}'
                      : 'Flush and summarise notifications on a schedule, regardless of threshold',
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
                value: settings.digestEnabled,
                onChanged: settings.setDigestEnabled,
              ),
              if (settings.digestEnabled) ...[
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  leading: const Icon(Icons.settings, color: Colors.white54),
                  title: const Text('Configure digest'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DigestSettingsScreen())),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Label('Summarisation'),
        _Card(
          child: Column(
            children: [
              // Summary length slider
              _SliderTile(
                icon: Icons.short_text,
                title: 'Summary length',
                subtitle: 'Detail level of generated summaries',
                valueLabel: _lengthLabel(settings.summaryLength),
                min: 1, max: 3, divisions: 2,
                value: settings.summaryLength.toDouble(),
                onChanged: (v) => settings.setSummaryLength(v.round()),
                minLabel: 'Brief',
                maxLabel: 'Detailed',
              ),
              const Divider(color: Colors.white10, height: 1),
              // Threshold slider
              _SliderTile(
                icon: Icons.filter_list,
                title: 'Summarise after',
                subtitle: settings.notificationThreshold == 1
                    ? 'Every notification will be summarised immediately'
                    : '${settings.notificationThreshold} notifications from the same app before summarising',
                valueLabel: settings.notificationThreshold == 1
                    ? 'Every 1'
                    : '${settings.notificationThreshold}',
                min: 1, max: 10, divisions: 9,
                value: settings.notificationThreshold.toDouble(),
                onChanged: (v) => settings.setNotificationThreshold(v.round()),
                minLabel: 'Every 1',
                maxLabel: '10',
              ),
              const Divider(color: Colors.white10, height: 1),
              // Global cooldown slider
              _SliderTile(
                icon: Icons.timer,
                title: 'Summary cooldown',
                subtitle: settings.summaryCooldownMs == 0
                    ? 'No cooldown — rapid-fire summaries allowed'
                    : 'Wait ${settings.summaryCooldownMs ~/ 1000}s before re-summarising the same app',
                valueLabel: settings.summaryCooldownMs == 0
                    ? 'Off'
                    : '${settings.summaryCooldownMs ~/ 1000}s',
                min: 0, max: 120000, divisions: 8,
                value: settings.summaryCooldownMs.toDouble(),
                onChanged: (v) => settings.setSummaryCooldownMs(v.round()),
                minLabel: 'Off',
                maxLabel: '120s',
              ),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.clear_all, color: Colors.white54),
                title: const Text('Dismiss original notifications'),
                subtitle: const Text(
                    'Clear intercepted notifications and carry their actions (Reply, Mark as read) onto the summary',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
                value: settings.dismissOnAppUsage,
                onChanged: settings.setDismissOnAppUsage,
              ),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.touch_app_outlined, color: Colors.white54),
                title: const Text('Retain original actions'),
                subtitle: const Text('Keep Reply / Mark as read on summary notifications',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
                value: settings.retainOriginalActions,
                onChanged: settings.setRetainOriginalActions,
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.white54),
                title: const Text('Custom AI prompt'),
                subtitle: Text(
                  settings.customPrompt == SettingsProvider.defaultPrompt 
                    ? 'Using default prompt' 
                    : 'Custom prompt active',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PromptSettingsScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Label('Data'),
        _Card(
          child: ListTile(
            leading: const Icon(Icons.import_export, color: Colors.white54),
            title: const Text('Import / Export settings'),
            subtitle: const Text('Backup or restore all settings and selected apps',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ImportExportScreen())),
          ),
        ),
        const SizedBox(height: 24),
        _Label('About'),
        _Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white54),
            title: const Text('About Notify AI'),
            subtitle: const Text('Version info, supported providers',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _lengthLabel(int v) => v == 1 ? 'Brief' : v == 3 ? 'Detailed' : 'Medium';
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String valueLabel;
  final double min, max, value;
  final int divisions;
  final void Function(double) onChanged;
  final String minLabel, maxLabel;

  const _SliderTile({
    required this.icon, required this.title, required this.subtitle,
    required this.valueLabel, required this.min, required this.max,
    required this.divisions, required this.value, required this.onChanged,
    required this.minLabel, required this.maxLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(subtitle,
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              Text(valueLabel,
                  style: const TextStyle(
                      color: Color(0xFF6B9E78), fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF6B9E78),
              inactiveTrackColor: const Color(0xFF3A3A3A),
              thumbColor: const Color(0xFF6B9E78),
              overlayColor: const Color(0xFF6B9E78).withOpacity(0.2),
              trackHeight: 3,
            ),
            child: Slider(
              min: min, max: max, divisions: divisions, value: value,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel, style: const TextStyle(color: Colors.white30, fontSize: 11)),
              Text(maxLabel, style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF6B9E78), fontSize: 13,
                fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.hardEdge,
        child: child,
      );
}
