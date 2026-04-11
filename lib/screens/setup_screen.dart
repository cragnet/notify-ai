import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/permissions_service.dart';
import 'main_shell.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  bool _notificationListener = false;
  bool _usageStats = false;
  bool _batteryOptimization = false;
  bool _postNotifications = true; // granted by default on older Android

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

  // Re-check when user returns from a system settings screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    final nl = await PermissionsService.isNotificationListenerEnabled();
    final us = await PermissionsService.isUsageStatsPermissionGranted();
    final bo = await PermissionsService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _notificationListener = nl;
        _usageStats = us;
        _batteryOptimization = bo;
      });
    }
  }

  bool get _allGranted =>
      _notificationListener && _usageStats && _batteryOptimization && _postNotifications;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final hasKey = settings.apiKeys.isNotEmpty ||
        settings.aiProvider == 'ollama' ||
        settings.aiProvider == 'gemini_nano';

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
                  const SizedBox(height: 24),

                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3A2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notify AI needs a few permissions and an AI API key to summarise your notifications.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showKeyInfo(context),
                          child: const Text('Where to get API keys →',
                              style: TextStyle(
                                  color: Color(0xFF6B9E78),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  _PermissionRow(
                    title: 'AI API key',
                    subtitle: settings.aiProvider == 'ollama' || settings.aiProvider == 'gemini_nano'
                        ? 'No key needed for ${settings.aiProvider == 'ollama' ? 'Ollama' : 'Gemini Nano'}'
                        : 'Stored encrypted on this device only',
                    granted: hasKey,
                    onTap: () => _showProviderSheet(context),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'Notification access',
                    subtitle: 'Required to read incoming notifications',
                    granted: _notificationListener,
                    onTap: () => PermissionsService.openNotificationListenerSettings(),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'Send notifications',
                    subtitle: 'Required to post AI summary notifications',
                    granted: _postNotifications,
                    onTap: () => setState(() => _postNotifications = true),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'App usage access',
                    subtitle: 'Detect when you open an app to dismiss summaries',
                    granted: _usageStats,
                    onTap: () => PermissionsService.openUsageStatsSettings(),
                  ),
                  const SizedBox(height: 20),
                  _PermissionRow(
                    title: 'Disable battery optimisation',
                    subtitle: 'Keeps the service running in the background',
                    granted: _batteryOptimization,
                    onTap: () => PermissionsService.requestIgnoreBatteryOptimization(),
                  ),

                  const SizedBox(height: 48),

                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: (_allGranted && hasKey)
                              ? () async {
                                  await settings.completeSetup();
                                  if (context.mounted) {
                                    Navigator.pushReplacement(context,
                                        MaterialPageRoute(builder: (_) => const MainShell()));
                                  }
                                }
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_allGranted && hasKey)
                                  ? const Color(0xFF6B9E78)
                                  : const Color(0xFF2A2A2A),
                            ),
                            child: const Icon(Icons.arrow_forward, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (_allGranted && hasKey)
                              ? 'Tap to continue'
                              : 'Complete steps above to continue',
                          style: TextStyle(
                            color: (_allGranted && hasKey) ? Colors.white60 : Colors.white30,
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

  void _showKeyInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Where to get API keys',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _infoRow('Claude (Anthropic)', 'console.anthropic.com'),
            _infoRow('OpenAI', 'platform.openai.com/api-keys'),
            _infoRow('OpenRouter', 'openrouter.ai/keys'),
            _infoRow('Google Gemini', 'aistudio.google.com/app/apikey'),
            _infoRow('Ollama / Gemini Nano', 'No key needed'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
                width: 150,
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(color: Color(0xFF6B9E78), fontSize: 13))),
          ],
        ),
      );

  void _showProviderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<SettingsProvider>(),
        child: const _QuickProviderSheet(),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.granted,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                granted ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(granted),
                color: granted ? const Color(0xFF6B9E78) : Colors.white30,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: granted ? Colors.white : Colors.white70)),
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

class _QuickProviderSheet extends StatefulWidget {
  const _QuickProviderSheet();

  @override
  State<_QuickProviderSheet> createState() => _QuickProviderSheetState();
}

class _QuickProviderSheetState extends State<_QuickProviderSheet> {
  String _provider = 'claude';
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: 'http://10.0.1.33:11434');
  bool _obscure = true;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final noKey = _provider == 'ollama' || _provider == 'gemini_nano';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose AI provider',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _provider,
            dropdownColor: const Color(0xFF2A2A2A),
            decoration: const InputDecoration(labelText: 'Provider'),
            items: const [
              DropdownMenuItem(value: 'claude', child: Text('Claude (Anthropic)')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
              DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
              DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
              DropdownMenuItem(value: 'gemini_nano', child: Text('Gemini Nano (on-device)')),
              DropdownMenuItem(value: 'ollama', child: Text('Ollama (local/Pi)')),
            ],
            onChanged: (v) {
              if (v != null) setState(() {
                _provider = v;
                _keyCtrl.text = settings.getApiKey(v);
              });
            },
          ),
          const SizedBox(height: 12),
          if (_provider == 'ollama') ...[
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'Ollama URL'),
            ),
            const SizedBox(height: 4),
            const Text('Default: your Pi at http://10.0.1.33:11434',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ] else if (!noKey) ...[
            TextFormField(
              controller: _keyCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _provider == 'gemini_nano'
                    ? 'Gemini Nano runs entirely on your device — no API key needed.'
                    : 'Ollama runs on your local network — no API key needed.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await settings.setAiProvider(_provider);
                if (_provider == 'ollama') {
                  await settings.setBaseUrl('ollama', _urlCtrl.text.trim());
                } else if (!noKey && _keyCtrl.text.isNotEmpty) {
                  await settings.setApiKey(_provider, _keyCtrl.text.trim());
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save & continue'),
            ),
          ),
        ],
      ),
    );
  }
}
