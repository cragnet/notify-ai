import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import 'dart:convert';
import 'dart:io';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  bool _exporting = false;
  bool _importing = false;
  String? _statusMessage;
  bool _statusSuccess = true;

  Future<void> _export() async {
    setState(() { _exporting = true; _statusMessage = null; });
    try {
      final settings = context.read<SettingsProvider>();
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
        'note': 'API keys are not exported for security.',
      };

      final json = const JsonEncoder.withIndent('  ').convert(export);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/notify_ai_settings.json');
      await file.writeAsString(json);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Notify AI Settings Export',
      );

      setState(() {
        _exporting = false;
        _statusMessage = 'Export shared — save the file somewhere safe';
        _statusSuccess = true;
      });
    } catch (e) {
      setState(() { _exporting = false; _statusMessage = 'Export failed: $e'; _statusSuccess = false; });
    }
  }

  Future<void> _importFromFile() async {
    setState(() { _importing = true; _statusMessage = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() { _importing = false; _statusMessage = 'No file selected'; _statusSuccess = false; });
        return;
      }

      final path = result.files.single.path;
      if (path == null) {
        setState(() { _importing = false; _statusMessage = 'Could not read file path'; _statusSuccess = false; });
        return;
      }

      final text = await File(path).readAsString();
      await _applyImport(text);
    } catch (e) {
      setState(() { _importing = false; _statusMessage = 'Import failed: $e'; _statusSuccess = false; });
    }
  }

  Future<void> _applyImport(String text) async {
    try {
      final settings = context.read<SettingsProvider>();
      final Map<String, dynamic> data = jsonDecode(text);

      if (data['version'] == null) throw Exception('Invalid export file — missing version');

      final s = data['settings'] as Map<String, dynamic>? ?? {};
      final models = data['provider_models'] as Map<String, dynamic>? ?? {};
      final urls = data['provider_base_urls'] as Map<String, dynamic>? ?? {};
      final apps = (data['enabled_apps'] as List?)?.cast<String>() ?? [];

      if (s['ai_provider'] != null) await settings.setAiProvider(s['ai_provider']);
      if (s['summary_length'] != null) await settings.setSummaryLength(s['summary_length']);
      if (s['notification_threshold'] != null) await settings.setNotificationThreshold(s['notification_threshold']);
      if (s['dismiss_on_app_usage'] != null) await settings.setDismissOnAppUsage(s['dismiss_on_app_usage']);
      if (s['retain_original_actions'] != null) await settings.setRetainOriginalActions(s['retain_original_actions']);
      if (s['service_enabled'] != null) await settings.setServiceEnabled(s['service_enabled']);

      for (final e in models.entries) await settings.setModel(e.key, e.value.toString());
      for (final e in urls.entries) await settings.setBaseUrl(e.key, e.value.toString());
      await settings.setEnabledApps(apps.toSet());

      setState(() {
        _importing = false;
        _statusMessage = 'Import successful — ${apps.length} apps restored. Re-enter your API keys.';
        _statusSuccess = true;
      });
    } catch (e) {
      setState(() { _importing = false; _statusMessage = 'Import failed: $e'; _statusSuccess = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import / Export'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (_statusMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _statusSuccess ? const Color(0xFF2A3A2E) : const Color(0xFF3A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(_statusSuccess ? Icons.check_circle : Icons.error_outline,
                        color: _statusSuccess ? const Color(0xFF6B9E78) : Colors.redAccent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusMessage!,
                        style: TextStyle(color: _statusSuccess ? const Color(0xFF6B9E78) : Colors.redAccent, fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            _Label('Export settings'),
            _Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Exports all settings, provider config, and selected apps to a JSON file. API keys are not included.',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.share_outlined),
                  label: Text(_exporting ? 'Exporting...' : 'Export to file'),
                )),
              ]),
            )),

            const SizedBox(height: 16),

            _Label('Import settings'),
            _Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Select a previously exported JSON file to restore all settings. You will need to re-enter your API keys afterwards.',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: _importing ? null : _importFromFile,
                  icon: _importing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(_importing ? 'Importing...' : 'Select file to import'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A4A7A)),
                )),
              ]),
            )),
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
