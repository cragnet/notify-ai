import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/permissions_service.dart';

class DigestSettingsScreen extends StatelessWidget {
  const DigestSettingsScreen({super.key});

  static const List<({String value, String label, IconData icon})> _scheduleTypes = [
    (value: 'fixed_times', label: 'Fixed times', icon: Icons.schedule),
    (value: 'interval', label: 'Interval', icon: Icons.timelapse),
    (value: 'daily', label: 'Daily', icon: Icons.today),
    (value: 'weekly', label: 'Weekly', icon: Icons.calendar_view_week),
  ];

  static const List<({int value, String label})> _weekDays = [
    (value: 0, label: 'Sun'),
    (value: 1, label: 'Mon'),
    (value: 2, label: 'Tue'),
    (value: 3, label: 'Wed'),
    (value: 4, label: 'Thu'),
    (value: 5, label: 'Fri'),
    (value: 6, label: 'Sat'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digest Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Schedule type'),
            _Card(
              child: Column(
                children: _scheduleTypes.map((t) => RadioListTile<String>(
                  title: Text(t.label),
                  secondary: Icon(t.icon, color: Colors.white54),
                  value: t.value,
                  groupValue: settings.digestScheduleType,
                  activeColor: const Color(0xFF6B9E78),
                  onChanged: (v) => settings.setDigestScheduleType(v!),
                )).toList(),
              ),
            ),
            const SizedBox(height: 24),
            _buildScheduleConfig(context, settings),
            const SizedBox(height: 24),
            _SectionLabel('Apps to include'),
            _Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('All monitored apps'),
                    subtitle: const Text('Include every app in digest summaries',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    value: 'all',
                    groupValue: settings.digestAppFilter,
                    activeColor: const Color(0xFF6B9E78),
                    onChanged: (v) => settings.setDigestAppFilter(v!),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  RadioListTile<String>(
                    title: const Text('Include only selected apps'),
                    subtitle: const Text('Digest only specific apps',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    value: 'include_only',
                    groupValue: settings.digestAppFilter,
                    activeColor: const Color(0xFF6B9E78),
                    onChanged: (v) => settings.setDigestAppFilter(v!),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  RadioListTile<String>(
                    title: const Text('Exclude specific apps'),
                    subtitle: const Text('Include all except chosen apps',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    value: 'exclude',
                    groupValue: settings.digestAppFilter,
                    activeColor: const Color(0xFF6B9E78),
                    onChanged: (v) => settings.setDigestAppFilter(v!),
                  ),
                ],
              ),
            ),
            if (settings.digestAppFilter != 'all') ...[
              const SizedBox(height: 12),
              _buildAppSelector(context, settings),
            ],
            const SizedBox(height: 24),
            _SectionLabel('Digest AI prompt'),
            _Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.white54),
                title: const Text('Custom digest prompt'),
                subtitle: Text(
                  settings.digestPrompt.isEmpty ? 'Using default prompt' : 'Custom prompt active',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DigestPromptScreen()),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleConfig(BuildContext context, SettingsProvider settings) {
    switch (settings.digestScheduleType) {
      case 'fixed_times':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Fixed times'),
            _Card(
              child: Column(
                children: [
                  if (settings.digestTimes.isNotEmpty)
                    ...settings.digestTimes.asMap().entries.map((e) {
                      final isLast = e.key == settings.digestTimes.length - 1;
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.access_time, color: Colors.white54),
                            title: Text(e.value),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white38),
                              onPressed: () => settings.removeDigestTime(e.value),
                            ),
                          ),
                          if (!isLast) const Divider(color: Colors.white10, height: 1),
                        ],
                      );
                    }),
                  if (settings.digestTimes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No times added',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  const Divider(color: Colors.white10, height: 1),
                  ListTile(
                    leading: const Icon(Icons.add, color: Color(0xFF6B9E78)),
                    title: const Text('Add time', style: TextStyle(color: Color(0xFF6B9E78))),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        final formatted =
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                        await settings.addDigestTime(formatted);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      case 'interval':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Interval'),
            _Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timelapse, color: Colors.white54, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Every', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        DropdownButton<int>(
                          value: settings.digestIntervalMinutes,
                          dropdownColor: const Color(0xFF2A2A2A),
                          style: const TextStyle(color: Colors.white),
                          underline: Container(height: 1, color: Colors.white24),
                          items: [15, 30, 60, 120, 180, 240, 360, 480, 720]
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      m < 60
                                          ? '$m min'
                                          : m % 60 == 0
                                              ? '${m ~/ 60} hr'
                                              : '${m ~/ 60}h ${m % 60}m',
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => settings.setDigestIntervalMinutes(v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Digest will fire every interval while notifications are pending.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'daily':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Daily time'),
            _Card(
              child: ListTile(
                leading: const Icon(Icons.access_time, color: Colors.white54),
                title: const Text('Time of day'),
                subtitle: Text(settings.digestDailyTime,
                    style: const TextStyle(color: Colors.white38)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () async {
                  final parts = settings.digestDailyTime.split(':');
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.tryParse(parts[0]) ?? 9,
                      minute: int.tryParse(parts[1]) ?? 0,
                    ),
                  );
                  if (time != null) {
                    final formatted =
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    await settings.setDigestDailyTime(formatted);
                  }
                },
              ),
            ),
          ],
        );
      case 'weekly':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Weekly schedule'),
            _Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white54, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Day of week', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        DropdownButton<int>(
                          value: settings.digestWeeklyDay,
                          dropdownColor: const Color(0xFF2A2A2A),
                          style: const TextStyle(color: Colors.white),
                          underline: Container(height: 1, color: Colors.white24),
                          items: _weekDays
                              .map((d) => DropdownMenuItem(
                                    value: d.value,
                                    child: Text(d.label),
                                  ))
                              .toList(),
                          onChanged: (v) => settings.setDigestWeeklyDay(v!),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  ListTile(
                    leading: const Icon(Icons.access_time, color: Colors.white54),
                    title: const Text('Time of day'),
                    subtitle: Text(settings.digestWeeklyTime,
                        style: const TextStyle(color: Colors.white38)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () async {
                      final parts = settings.digestWeeklyTime.split(':');
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: int.tryParse(parts[0]) ?? 9,
                          minute: int.tryParse(parts[1]) ?? 0,
                        ),
                      );
                      if (time != null) {
                        final formatted =
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                        await settings.setDigestWeeklyTime(formatted);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAppSelector(BuildContext context, SettingsProvider settings) {
    return FutureBuilder<List<Map<String, String>>>(
      future: PermissionsService.getInstalledApps(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF6B9E78)));
        }
        final apps = snapshot.data!;
        final filtered = apps
            .where((a) => settings.enabledApps.contains(a['packageName']))
            .toList();
        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No monitored apps to select',
                style: TextStyle(color: Colors.white38)),
          );
        }
        return _Card(
          child: Column(
            children: filtered.asMap().entries.map((e) {
              final app = e.value;
              final pkg = app['packageName']!;
              final name = app['appName']!;
              final isSelected = settings.digestAppList.contains(pkg);
              final isLast = e.key == filtered.length - 1;
              return Column(
                children: [
                  CheckboxListTile(
                    title: Text(name),
                    subtitle: Text(pkg,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    value: isSelected,
                    activeColor: const Color(0xFF6B9E78),
                    onChanged: (_) => settings.toggleDigestApp(pkg),
                  ),
                  if (!isLast) const Divider(color: Colors.white10, height: 1),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class DigestPromptScreen extends StatefulWidget {
  const DigestPromptScreen({super.key});

  @override
  State<DigestPromptScreen> createState() => _DigestPromptScreenState();
}

class _DigestPromptScreenState extends State<DigestPromptScreen> {
  late TextEditingController _promptController;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final settings = context.read<SettingsProvider>();
    setState(() {
      _promptController = TextEditingController(text: settings.getDigestPrompt());
    });
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setDigestPrompt(_promptController.text);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _resetToDefault() {
    setState(() {
      _promptController.text = SettingsProvider.defaultDigestPrompt;
      _saved = false;
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDefault = _promptController.text == SettingsProvider.defaultDigestPrompt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digest Prompt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 600;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? constraints.maxWidth * 0.15 : 16,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('Digest AI Prompt'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _promptController,
                          maxLines: 12,
                          minLines: 8,
                          decoration: const InputDecoration(
                            hintText: 'Enter your digest prompt...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 14, height: 1.5),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isDefault ? 'Using default prompt' : 'Custom prompt active',
                        style: TextStyle(
                          color: isDefault ? Colors.white38 : const Color(0xFF6B9E78),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!isDefault)
                      TextButton(
                        onPressed: _resetToDefault,
                        child: const Text('Reset to default'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saved ? null : _save,
                    icon: _saved
                        ? const Icon(Icons.check, size: 18)
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saved ? 'Saved' : 'Save prompt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _saved ? const Color(0xFF6B9E78) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _SectionLabel('Purpose'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'This prompt is used specifically for digest summaries — periodic rollups of accumulated notifications. '
                    'Unlike the main prompt which handles real-time batches, digests cover a longer time window and may span multiple apps. '
                    'Consider instructing the AI to prioritise urgent items, group by topic, and highlight actionable messages.',
                    style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('Variables'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VariableItem('{notifications}', 'The grouped notification content'),
                      Divider(color: Colors.white10, height: 16),
                      _VariableItem('{app_name}', 'Name of the app(s)'),
                      Divider(color: Colors.white10, height: 16),
                      _VariableItem('{count}', 'Number of notifications'),
                      Divider(color: Colors.white10, height: 16),
                      _VariableItem('{length}', 'Summary length (1=brief, 2=balanced, 3=detailed)'),
                      Divider(color: Colors.white10, height: 16),
                      _VariableItem('{length_instruction}', 'Full length instruction text'),
                      Divider(color: Colors.white10, height: 16),
                      _VariableItem('{hint}', 'Concise length hint'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF6B9E78),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.hardEdge,
    child: child,
  );
}

class _VariableItem extends StatelessWidget {
  final String name;
  final String description;
  const _VariableItem(this.name, this.description);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3A2E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Color(0xFF6B9E78),
              fontSize: 12,
              fontFamily: 'monospace',
              fontFamilyFallback: ['Courier'],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
