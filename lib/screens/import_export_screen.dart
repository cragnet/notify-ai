import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';
import 'dart:convert';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  bool _exporting = false;
  bool _importing = false;
  String? _exportJson;
  String? _statusMessage;
  bool _statusSuccess = true;
  final _importCtrl = TextEditingController();

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() { _exporting = true; _statusMessage = null; });
    try {
      final settings = context.read<SettingsProvider>();
      final prefs = await SharedPreferences.getInstance();

      // Build export object with all configurable settings
      final export = {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'settings': {
          'ai_provider': settings.aiProvider,
          'summary_length': settings.summaryLength,
          'notification_threshold': settings.notificationThreshold,
          'dismiss_on_app_usage': settings.dismissOnAppUsage,
          'retain_original_actions': settings.retainOriginalActions,
          'service_enabled': settings.serviceEnabled,
        },
        'provider_models': settings.providerModels,
        'provider_base_urls': settings.providerBaseUrls,
        'enabled_apps': settings.enabledApps.toList()..sort(),
        // Note: API keys are NOT exported for security
        'note': 'API keys are not exported. Re-enter them after importing.',
      };

      final json = const JsonEncoder.withIndent('  ').convert(export);
      setState(() {
        _exportJson = json;
        _exporting = false;
        _statusMessage = 'Export ready — copy or share below';
        _statusSuccess = true;
      });
    } catch (e) {
      setState(() {
        _exporting = false;
        _statusMessage = 'Export failed: $e';
        _statusSuccess = false;
      });
    }
  }

  Future<void> _import() async {
    final text = _importCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusMessage = 'Paste your exported JSON first';
        _statusSuccess = false;
      });
      return;
    }

    setState(() { _importing = true; _statusMessage = null; });

    try {
      final settings = context.read<SettingsProvider>();
      final Map<String, dynamic> data = jsonDecode(text);

      // Validate
      if (data['version'] == null) throw Exception('Invalid export file — missing version');

      final s = data['settings'] as Map<String, dynamic>? ?? {};
      final models = data['provider_models'] as Map<String, dynamic>? ?? {};
      final urls = data['provider_base_urls'] as Map<String, dynamic>? ?? {};
      final apps = (data['enabled_apps'] as List?)?.cast<String>() ?? [];

      // Apply settings
      if (s['ai_provider'] != null) await settings.setAiProvider(s['ai_provider']);
      if (s['summary_length'] != null) await settings.setSummaryLength(s['summary_length']);
      if (s['notification_threshold'] != null) await settings.setNotificationThreshold(s['notification_threshold']);
      if (s['dismiss_on_app_usage'] != null) await settings.setDismissOnAppUsage(s['dismiss_on_app_usage']);
      if (s['retain_original_actions'] != null) await settings.setRetainOriginalActions(s['retain_original_actions']);
      if (s['service_enabled'] != null) await settings.setServiceEnabled(s['service_enabled']);

      // Apply models and URLs
      for (final entry in models.entries) {
        await settings.setModel(entry.key, entry.value.toString());
      }
      for (final entry in urls.entries) {
        await settings.setBaseUrl(entry.key, entry.value.toString());
      }

      // Apply selected apps
      await settings.setEnabledApps(apps.toSet());

      setState(() {
        _importing = false;
        _statusMessage = 'Import successful — ${apps.length} apps restored. Re-enter your API keys in Settings.';
        _statusSuccess = true;
        _importCtrl.clear();
      });
    } catch (e) {
      setState(() {
        _importing = false;
        _statusMessage = 'Import failed: $e';
        _statusSuccess = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import / Export'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Status message
            if (_statusMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _statusSuccess
                      ? const Color(0xFF2A3A2E)
                      : const Color(0xFF3A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusSuccess ? Icons.check_circle : Icons.error_outline,
                      color: _statusSuccess ? const Color(0xFF6B9E78) : Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _statusSuccess ? const Color(0xFF6B9E78) : Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Export ──────────────────────────────────────────────────
            _Label('Export settings'),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Exports all settings, provider configuration, and selected apps. API keys are not included for security.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.upload_outlined),
                      label: Text(_exporting ? 'Exporting...' : 'Generate export'),
                    ),
                  ),

                  if (_exportJson != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('JSON',
                                  style: TextStyle(color: Colors.white38, fontSize: 12)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: _exportJson!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                      backgroundColor: Color(0xFF4A7A56),
                                    ),
                                  );
                                },
                                child: const Row(
                                  children: [
                                    Icon(Icons.copy, color: Color(0xFF6B9E78), size: 14),
                                    SizedBox(width: 4),
                                    Text('Copy',
                                        style: TextStyle(
                                            color: Color(0xFF6B9E78), fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _exportJson!,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'monospace'),
                            maxLines: 20,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Import ──────────────────────────────────────────────────
            _Label('Import settings'),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste a previously exported JSON to restore all settings. You will need to re-enter your API keys afterwards.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _importCtrl,
                    maxLines: 8,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'Paste exported JSON here...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _importing ? null : _import,
                      icon: _importing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_outlined),
                      label: Text(_importing ? 'Importing...' : 'Import settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2A4A7A),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
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
                color: Color(0xFF6B9E78),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );
}
