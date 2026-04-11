import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../models/provider_config.dart';

class ProviderSettingsScreen extends StatefulWidget {
  const ProviderSettingsScreen({super.key});

  @override
  State<ProviderSettingsScreen> createState() => _ProviderSettingsScreenState();
}

class _ProviderSettingsScreenState extends State<ProviderSettingsScreen> {
  late String _selectedProvider;
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
      _keyCtrl.text = s.getApiKey(_selectedProvider);
      _urlCtrl.text = s.getBaseUrl(_selectedProvider);
      _modelCtrl.text = s.getModel(_selectedProvider);
    });
  }

  void _switchProvider(String id) {
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
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  ProviderConfig? get _cfg => providerById(_selectedProvider);

  Future<void> _save() async {
    final s = context.read<SettingsProvider>();
    final cfg = _cfg;
    if (cfg == null) return;

    await s.setAiProvider(_selectedProvider);
    await s.setApiKey(_selectedProvider, _keyCtrl.text.trim());
    await s.setBaseUrl(_selectedProvider, _urlCtrl.text.trim());
    final model = _modelCtrl.text.trim();
    if (model.isNotEmpty) {
      await s.setModel(_selectedProvider, model);
    }

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider'),
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
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Provider selector ──────────────────────────────────────
                _Label('Provider'),
                _Card(
                  child: Column(
                    children: kProviders.asMap().entries.map((entry) {
                      final p = entry.value;
                      final isLast = entry.key == kProviders.length - 1;
                      return Column(
                        children: [
                          RadioListTile<String>(
                            value: p.id,
                            groupValue: _selectedProvider,
                            activeColor: const Color(0xFF6B9E78),
                            title: Text(p.displayName),
                            subtitle: _subtitle(p),
                            onChanged: (v) { if (v != null) _switchProvider(v); },
                          ),
                          if (!isLast) const Divider(color: Colors.white10, height: 1),
                        ],
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),
                _Label('Configuration'),
                _Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // API Key
                        if (cfg?.needsApiKey == true || cfg?.apiKeyOptional == true) ...[
                          _FieldLabel('API Key${cfg?.apiKeyOptional == true ? ' (optional)' : ''}'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _keyCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              hintText: cfg?.keyHint ?? 'Enter API key',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.white38, size: 20,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            onChanged: (_) => setState(() => _saved = false),
                          ),
                          const SizedBox(height: 4),
                          const Text('Stored encrypted on device — never shared',
                              style: TextStyle(color: Colors.white30, fontSize: 11)),
                          const SizedBox(height: 16),
                        ] else if (cfg?.id == 'gemini_nano') ...[
                          _InfoBox(
                            icon: Icons.lock_open,
                            text: 'No API key needed — runs entirely on your device',
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Base URL
                        if (cfg?.needsBaseUrl == true) ...[
                          _FieldLabel('Base URL (optional)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _urlCtrl,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: cfg?.urlHint ?? 'https://',
                            ),
                            onChanged: (_) => setState(() => _saved = false),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cfg?.id == 'local'
                                ? 'IP and port of your local server — e.g. http://192.168.1.50:11434'
                                : cfg?.id == 'ollama'
                                    ? 'Full URL of your Ollama instance — leave blank if not yet set up'
                                    : 'Leave blank to use the default endpoint',
                            style: const TextStyle(color: Colors.white30, fontSize: 11),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Model — always free text, no dropdown
                        _FieldLabel('Model'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _modelCtrl,
                          decoration: InputDecoration(
                            hintText: cfg?.modelHint ?? 'Enter model name',
                          ),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Type the exact model identifier',
                          style: TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _saved
                        ? Container(
                            key: const ValueKey('saved'),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A3A2E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle,
                                    color: Color(0xFF6B9E78), size: 20),
                                SizedBox(width: 8),
                                Text('Configuration saved',
                                    style: TextStyle(
                                        color: Color(0xFF6B9E78),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16)),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            key: const ValueKey('save'),
                            onPressed: _save,
                            child: const Text('Save configuration',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget? _subtitle(ProviderConfig p) {
    String? text;
    if (p.id == 'gemini_nano') text = 'Requires Pixel 8+ or compatible device';
    if (p.id == 'local') text = 'Any OpenAI-compatible local server';
    if (p.id == 'ollama') text = 'Cloud-hosted or self-hosted Ollama instance';
    if (text == null) return null;
    return Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12));
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13));
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A3A2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6B9E78), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text,
                style: const TextStyle(color: Colors.white70, fontSize: 13))),
          ],
        ),
      );
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
