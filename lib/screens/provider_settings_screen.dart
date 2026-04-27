import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/settings_provider.dart';
import '../models/provider_config.dart';
import 'dart:io';

class ProviderSettingsScreen extends StatefulWidget {
  const ProviderSettingsScreen({super.key});

  @override
  State<ProviderSettingsScreen> createState() => _ProviderSettingsScreenState();
}

class _ProviderSettingsScreenState extends State<ProviderSettingsScreen> {
  late String _selectedProvider;
  String _backupProvider1 = '';
  String _backupProvider2 = '';
  final _wifiSsid1Ctrl = TextEditingController();
  String _wifiProvider1 = '';
  final _wifiSsid2Ctrl = TextEditingController();
  String _wifiProvider2 = '';
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _obscure = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final s = context.read<SettingsProvider>();
    setState(() {
      _selectedProvider = s.aiProvider;
      // Default to ollama if current provider no longer exists
      if (providerById(_selectedProvider) == null) _selectedProvider = 'ollama';
      _backupProvider1 = s.backupProvider1;
      _backupProvider2 = s.backupProvider2;
      _wifiSsid1Ctrl.text = s.wifiSsid1;
      _wifiProvider1 = s.wifiProvider1;
      _wifiSsid2Ctrl.text = s.wifiSsid2;
      _wifiProvider2 = s.wifiProvider2;
      _keyCtrl.text = s.getApiKey(_selectedProvider);
      _urlCtrl.text = s.getBaseUrl(_selectedProvider);
      _modelCtrl.text = s.getModel(_selectedProvider);
    });
  }

  void _switch(String id) {
    final s = context.read<SettingsProvider>();
    setState(() {
      _selectedProvider = id;
      _keyCtrl.text = s.getApiKey(id);
      _urlCtrl.text = s.getBaseUrl(id);
      _modelCtrl.text = s.getModel(id);
      _saved = false;
    });
  }

  @override
  void dispose() {
    _wifiSsid1Ctrl.dispose(); _wifiSsid2Ctrl.dispose();
    _keyCtrl.dispose(); _urlCtrl.dispose(); _modelCtrl.dispose();
    super.dispose();
  }

  ProviderConfig? get _cfg => providerById(_selectedProvider);

  Future<void> _save() async {
    final s = context.read<SettingsProvider>();
    await s.setAiProvider(_selectedProvider);
    await s.setBackupProvider1(_backupProvider1);
    await s.setBackupProvider2(_backupProvider2);
    await s.setWifiSsid1(_wifiSsid1Ctrl.text.trim());
    await s.setWifiProvider1(_wifiProvider1);
    await s.setWifiSsid2(_wifiSsid2Ctrl.text.trim());
    await s.setWifiProvider2(_wifiProvider2);
    if (_keyCtrl.text.isNotEmpty) await s.setApiKey(_selectedProvider, _keyCtrl.text.trim());
    if (_urlCtrl.text.isNotEmpty) await s.setBaseUrl(_selectedProvider, _urlCtrl.text.trim());
    if (_modelCtrl.text.isNotEmpty) await s.setModel(_selectedProvider, _modelCtrl.text.trim());
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _saved = false); });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > 600;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? constraints.maxWidth * 0.15 : 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _Label('Provider'),
            _Card(child: Column(children: kProviders.asMap().entries.map((entry) {
              final p = entry.value;
              final isLast = entry.key == kProviders.length - 1;
              return Column(children: [
                RadioListTile<String>(
                  value: p.id, groupValue: _selectedProvider,
                  activeColor: const Color(0xFF6B9E78),
                  title: Text(p.displayName),
                  subtitle: _subtitle(p),
                  onChanged: (v) { if (v != null) _switch(v); },
                ),
                if (!isLast) const Divider(color: Colors.white10, height: 1),
              ]);
            }).toList())),

            const SizedBox(height: 16),
            _Label('Backup provider 1'),
            _Card(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                value: _backupProvider1.isEmpty ? null : _backupProvider1,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'None (disabled)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (disabled)', style: TextStyle(color: Colors.white38))),
                  ...kProviders.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName, style: const TextStyle(color: Colors.white70)))),
                ],
                onChanged: (v) { setState(() { _backupProvider1 = v ?? ''; _saved = false; }); },
                dropdownColor: const Color(0xFF2A2A2A),
              ),
            )),
            const SizedBox(height: 8),
            _Label('Backup provider 2'),
            _Card(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                value: _backupProvider2.isEmpty ? null : _backupProvider2,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'None (disabled)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (disabled)', style: TextStyle(color: Colors.white38))),
                  ...kProviders.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName, style: const TextStyle(color: Colors.white70)))),
                ],
                onChanged: (v) { setState(() { _backupProvider2 = v ?? ''; _saved = false; }); },
                dropdownColor: const Color(0xFF2A2A2A),
              ),
            )),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('Backups use the model, URL and API key already configured for each provider. If the primary fails, the app tries backup 1, then backup 2.', style: TextStyle(color: Colors.white30, fontSize: 11)),
            ),
            const SizedBox(height: 16),
            _Label('WiFi-based provider 1'),
            _Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _FieldLabel('WiFi SSID'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _wifiSsid1Ctrl,
                  decoration: const InputDecoration(hintText: 'e.g. HomeWiFi_5G'),
                  onChanged: (_) => setState(() => _saved = false),
                ),
                const SizedBox(height: 4),
                const Text('Exact network name — case sensitive', style: TextStyle(color: Colors.white30, fontSize: 11)),
                const SizedBox(height: 16),
                _FieldLabel('Provider to use on this WiFi'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _wifiProvider1.isEmpty ? null : _wifiProvider1,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'None (disabled)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None (disabled)', style: TextStyle(color: Colors.white38))),
                    ...kProviders.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName, style: const TextStyle(color: Colors.white70)))),
                  ],
                  onChanged: (v) { setState(() { _wifiProvider1 = v ?? ''; _saved = false; }); },
                  dropdownColor: const Color(0xFF2A2A2A),
                ),
              ]),
            )),
            const SizedBox(height: 8),
            _Label('WiFi-based provider 2'),
            _Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _FieldLabel('WiFi SSID'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _wifiSsid2Ctrl,
                  decoration: const InputDecoration(hintText: 'e.g. Office_Guest'),
                  onChanged: (_) => setState(() => _saved = false),
                ),
                const SizedBox(height: 4),
                const Text('Exact network name — case sensitive', style: TextStyle(color: Colors.white30, fontSize: 11)),
                const SizedBox(height: 16),
                _FieldLabel('Provider to use on this WiFi'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _wifiProvider2.isEmpty ? null : _wifiProvider2,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'None (disabled)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None (disabled)', style: TextStyle(color: Colors.white38))),
                    ...kProviders.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName, style: const TextStyle(color: Colors.white70)))),
                  ],
                  onChanged: (v) { setState(() { _wifiProvider2 = v ?? ''; _saved = false; }); },
                  dropdownColor: const Color(0xFF2A2A2A),
                ),
              ]),
            )),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('When connected to a matching WiFi network, that provider is used instead of the primary. Location permission may be required on Android 10+ to read the SSID.', style: TextStyle(color: Colors.white30, fontSize: 11)),
            ),
            const SizedBox(height: 16),
            _Label('Configuration'),
            _Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // API Key
                if (cfg?.needsApiKey == true || cfg?.apiKeyOptional == true) ...[
                  _FieldLabel('API Key${cfg?.apiKeyOptional == true ? " (optional)" : ""}'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: cfg?.keyHint ?? 'Enter API key',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_keyCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.ios_share, color: Colors.white38, size: 18),
                              tooltip: 'Export API key to file',
                              onPressed: () async {
                                final key = _keyCtrl.text;
                                // Copy to clipboard
                                await Clipboard.setData(ClipboardData(text: key));
                                // Write to file and share
                                try {
                                  final dir = await getTemporaryDirectory();
                                  final file = File('${dir.path}/notify_ai_${_selectedProvider}_key.txt');
                                  await file.writeAsString(key);
                                  await Share.shareXFiles(
                                    [XFile(file.path, mimeType: 'text/plain')],
                                    subject: 'Notify AI — ${_selectedProvider} API key',
                                  );
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text('Export failed: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ));
                                  }
                                }
                              },
                            ),
                          IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ],
                      ),
                    ),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 4),
                  const Text('Stored encrypted on device only', style: TextStyle(color: Colors.white30, fontSize: 11)),
                  const SizedBox(height: 16),
                ] else if (cfg?.id == 'gemini_nano') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF2A3A2E), borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.lock_open, color: Color(0xFF6B9E78), size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text('No API key needed — runs entirely on your device',
                          style: TextStyle(color: Colors.white70, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Base URL (Ollama only)
                if (cfg?.needsBaseUrl == true) ...[
                  _FieldLabel('Base URL'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(hintText: cfg?.urlHint ?? 'http://'),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 4),
                  const Text('IP address and port of your Ollama server\ne.g. http://192.168.1.50:11434 or Tailscale IP',
                      style: TextStyle(color: Colors.white30, fontSize: 11)),
                  const SizedBox(height: 16),
                ],

                // Model (free text, always shown except Gemini Nano)
                if (cfg?.id != 'gemini_nano') ...[
                  _FieldLabel('Model'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _modelCtrl,
                    decoration: InputDecoration(hintText: cfg?.modelHint ?? 'Enter model name'),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 4),
                  const Text('Enter the exact model name', style: TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ]),
            )),

            const SizedBox(height: 20),

            SizedBox(width: double.infinity, child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _saved
                  ? Container(
                      key: const ValueKey('saved'),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(color: const Color(0xFF2A3A2E), borderRadius: BorderRadius.circular(12)),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.check_circle, color: Color(0xFF6B9E78), size: 20),
                        SizedBox(width: 8),
                        Text('Configuration saved', style: TextStyle(color: Color(0xFF6B9E78), fontWeight: FontWeight.w600, fontSize: 16)),
                      ]))
                  : ElevatedButton(
                      key: const ValueKey('save'),
                      onPressed: _save,
                      child: const Text('Save configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            )),

            const SizedBox(height: 32),
          ]),
        );
      }),
    );
  }

  Widget? _subtitle(ProviderConfig p) {
    String? text;
    if (p.id == 'gemini_nano') text = 'Requires Pixel 8+ or compatible device — no API key needed';
    if (p.id == 'ollama') text = 'Self-hosted or cloud Ollama instance';
    if (p.id == 'gemini') text = 'Google Gemini API — get key at aistudio.google.com';
    if (text == null) return null;
    return Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12));
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13));
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
    child: Text(text, style: const TextStyle(color: Color(0xFF6B9E78), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.hardEdge,
    child: child,
  );
}
