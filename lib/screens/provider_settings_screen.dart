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
  final _customModelCtrl = TextEditingController();
  bool _obscure = true;
  bool _saved = false;
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromSettings());
  }

  void _loadFromSettings() {
    final settings = context.read<SettingsProvider>();
    setState(() {
      _selectedProvider = settings.aiProvider;
      _keyCtrl.text = settings.getApiKey(_selectedProvider);
      _urlCtrl.text = settings.getBaseUrl(_selectedProvider);
      _selectedModel = settings.getModel(_selectedProvider);
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  ProviderConfig? get _config => providerById(_selectedProvider);

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setAiProvider(_selectedProvider);
    if (_config?.needsApiKey == true && _keyCtrl.text.isNotEmpty) {
      await settings.setApiKey(_selectedProvider, _keyCtrl.text.trim());
    }
    if (_config?.needsBaseUrl == true && _urlCtrl.text.isNotEmpty) {
      await settings.setBaseUrl(_selectedProvider, _urlCtrl.text.trim());
    }
    if (_selectedModel != null) {
      await settings.setModel(_selectedProvider, _selectedModel!);
    }
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
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
                // ── Provider selector ───────────────────────────────────────
                _Label('Provider'),
                _Card(
                  child: Column(
                    children: kProviders.map((p) {
                      final selected = _selectedProvider == p.id;
                      return Column(
                        children: [
                          RadioListTile<String>(
                            value: p.id,
                            groupValue: _selectedProvider,
                            activeColor: const Color(0xFF6B9E78),
                            title: Text(p.displayName),
                            subtitle: p.id == 'gemini_nano'
                                ? const Text('Requires Pixel 8+ or supported device',
                                    style: TextStyle(color: Colors.white38, fontSize: 12))
                                : null,
                            onChanged: (v) {
                              if (v != null) {
                                final s = context.read<SettingsProvider>();
                                setState(() {
                                  _selectedProvider = v;
                                  _keyCtrl.text = s.getApiKey(v);
                                  _urlCtrl.text = s.getBaseUrl(v);
                                  _selectedModel = s.getModel(v);
                                  _saved = false;
                                });
                              }
                            },
                          ),
                          if (kProviders.last.id != p.id)
                            const Divider(color: Colors.white10, height: 1),
                        ],
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Configuration fields ────────────────────────────────────
                _Label('Configuration'),
                _Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // API Key
                        if (config?.needsApiKey == true) ...[
                          const Text('API Key',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _keyCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              hintText: 'Paste your API key here',
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscure ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.white38, size: 20),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            onChanged: (_) => setState(() => _saved = false),
                          ),
                          const SizedBox(height: 4),
                          const Text('Stored encrypted on device only',
                              style: TextStyle(color: Colors.white30, fontSize: 11)),
                          const SizedBox(height: 16),
                        ],

                        if (config?.needsApiKey == false && config?.id != 'openrouter') ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A3A2E),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_open,
                                    color: Color(0xFF6B9E78), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    config?.id == 'gemini_nano'
                                        ? 'No API key needed — runs entirely on your device'
                                        : 'No API key needed — connects to your local Ollama',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Base URL
                        if (config?.needsBaseUrl == true) ...[
                          const Text('Base URL (Optional)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _urlCtrl,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: config?.defaultBaseUrl ?? '',
                            ),
                            onChanged: (_) => setState(() => _saved = false),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            config?.id == 'ollama'
                                ? 'Your Pi\'s Tailscale/local IP — default: ${config?.defaultBaseUrl}'
                                : 'Leave blank to use the default endpoint',
                            style: const TextStyle(color: Colors.white30, fontSize: 11),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Model
                        const Text('Model',
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                                fontSize: 13)),
                        const SizedBox(height: 6),
                        if (config != null)
                          ...config.models.map((m) {
                            if (m.isCustom) {
                              return _CustomModelTile(
                                selected: _selectedModel != null &&
                                    !config.models.any(
                                        (x) => !x.isCustom && x.id == _selectedModel),
                                currentValue: _selectedModel ?? '',
                                onSelected: (v) => setState(() {
                                  _selectedModel = v;
                                  _saved = false;
                                }),
                              );
                            }
                            return RadioListTile<String>(
                              dense: true,
                              value: m.id,
                              groupValue: _selectedModel,
                              activeColor: const Color(0xFF6B9E78),
                              title: Text(m.name,
                                  style: const TextStyle(fontSize: 14)),
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) {
                                if (v != null) setState(() {
                                  _selectedModel = v;
                                  _saved = false;
                                });
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Save button ─────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
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
                                        fontWeight: FontWeight.w600)),
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
}

class _CustomModelTile extends StatefulWidget {
  final bool selected;
  final String currentValue;
  final void Function(String) onSelected;
  const _CustomModelTile(
      {required this.selected, required this.currentValue, required this.onSelected});

  @override
  State<_CustomModelTile> createState() => _CustomModelTileState();
}

class _CustomModelTileState extends State<_CustomModelTile> {
  final _ctrl = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _ctrl.text = widget.currentValue;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RadioListTile<bool>(
          dense: true,
          value: true,
          groupValue: widget.selected,
          activeColor: const Color(0xFF6B9E78),
          title: const Text('Custom model name…', style: TextStyle(fontSize: 14)),
          contentPadding: EdgeInsets.zero,
          onChanged: (_) => setState(() => _editing = true),
        ),
        if (_editing || widget.selected) ...[
          TextFormField(
            controller: _ctrl,
            autofocus: _editing,
            decoration: const InputDecoration(hintText: 'e.g. phi3:mini'),
            onFieldSubmitted: (v) {
              if (v.isNotEmpty) widget.onSelected(v);
              setState(() => _editing = false);
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
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
