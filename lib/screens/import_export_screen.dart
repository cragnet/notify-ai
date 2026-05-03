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
  bool _includeApiKeys = false;

  Future<void> _export() async {
    setState(() { _exporting = true; _statusMessage = null; });
    try {
      final settings = context.read<SettingsProvider>();
      final export = {
        'version': 2,
        'exported_at': DateTime.now().toIso8601String(),
        'settings': {
          'ai_provider': settings.aiProvider,
          'backup_provider_1': settings.backupProvider1,
          'backup_provider_2': settings.backupProvider2,
          'wifi_ssid_1': settings.wifiSsid1,
          'wifi_provider_1': settings.wifiProvider1,
          'wifi_ssid_2': settings.wifiSsid2,
          'wifi_provider_2': settings.wifiProvider2,
          'summary_length': settings.summaryLength,
          'notification_threshold': settings.notificationThreshold,
          'dismiss_on_app_usage': settings.dismissOnAppUsage,
          'retain_original_actions': settings.retainOriginalActions,
          'service_enabled': settings.serviceEnabled,
          'custom_prompt': settings.customPrompt,
        },
        'provider_models': settings.providerModels,
        'provider_base_urls': settings.providerBaseUrls,
        'notification_colors': settings.notificationColors.map((key, value) =>
          MapEntry(key, value)),
        'app_thresholds': settings.appThresholds,
        'app_cooldowns': settings.appCooldowns,
        'enabled_apps': settings.enabledApps.toList()..sort(),
        'include_api_keys': _includeApiKeys,
        'api_keys': _includeApiKeys ? settings.apiKeys : {},
        'note': _includeApiKeys
            ? 'WARNING: This export contains API keys. Store it securely!'
            : 'API keys are not exported. Toggle the switch above to include them.',
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
        _statusMessage = _includeApiKeys
            ? 'Export shared with API keys — store securely!'
            : 'Export shared — save the file somewhere safe';
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

      // Import notification colors if present
      final colors = data['notification_colors'] as Map<String, dynamic>? ?? {};
      for (final e in colors.entries) {
        final colorValue = e.value as int?;
        if (colorValue != null) {
          await settings.setNotificationColor(e.key, colorValue);
        }
      }

      // Import per-app thresholds if present
      final thresholds = data['app_thresholds'] as Map<String, dynamic>? ?? {};
      for (final e in thresholds.entries) {
        final thresholdValue = e.value as int?;
        if (thresholdValue != null) {
          await settings.setAppThreshold(e.key, thresholdValue);
        }
      }

      // Import per-app cooldowns if present
      final cooldowns = data['app_cooldowns'] as Map<String, dynamic>? ?? {};
      for (final e in cooldowns.entries) {
        final cooldownValue = e.value as int?;
        if (cooldownValue != null && cooldownValue > 0) {
          await settings.setAppCooldown(e.key, cooldownValue);
        }
      }

      // Import API keys if present
      final importedApiKeys = data['api_keys'] as Map<String, dynamic>? ?? {};
      var apiKeyCount = 0;
      for (final e in importedApiKeys.entries) {
        final key = e.value as String?;
        if (key != null && key.isNotEmpty) {
          await settings.importApiKey(e.key, key);
          apiKeyCount++;
        }
      }

      if (s['ai_provider'] != null) await settings.setAiProvider(s['ai_provider']);
      if (s['backup_provider_1'] != null) await settings.setBackupProvider1(s['backup_provider_1']);
      if (s['backup_provider_2'] != null) await settings.setBackupProvider2(s['backup_provider_2']);
      if (s['wifi_ssid_1'] != null) await settings.setWifiSsid1(s['wifi_ssid_1']);
      if (s['wifi_provider_1'] != null) await settings.setWifiProvider1(s['wifi_provider_1']);
      if (s['wifi_ssid_2'] != null) await settings.setWifiSsid2(s['wifi_ssid_2']);
      if (s['wifi_provider_2'] != null) await settings.setWifiProvider2(s['wifi_provider_2']);
      if (s['summary_length'] != null) await settings.setSummaryLength(s['summary_length']);
      if (s['notification_threshold'] != null) await settings.setNotificationThreshold(s['notification_threshold']);
      if (s['dismiss_on_app_usage'] != null) await settings.setDismissOnAppUsage(s['dismiss_on_app_usage']);
      if (s['retain_original_actions'] != null) await settings.setRetainOriginalActions(s['retain_original_actions']);
      if (s['service_enabled'] != null) await settings.setServiceEnabled(s['service_enabled']);
      if (s['custom_prompt'] != null) await settings.setCustomPrompt(s['custom_prompt']);

      for (final e in models.entries) await settings.setModel(e.key, e.value.toString());
      for (final e in urls.entries) await settings.setBaseUrl(e.key, e.value.toString());
      await settings.setEnabledApps(apps.toSet());

      setState(() {
        _importing = false;
        if (apiKeyCount > 0) {
          _statusMessage = 'Import successful — ${apps.length} apps restored, $apiKeyCount API key(s) imported.';
        } else {
          _statusMessage = 'Import successful — ${apps.length} apps restored. Re-enter your API keys.';
        }
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
                const Text('Exports all settings, provider config, and selected apps to a JSON file.',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Include API keys',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text('WARNING: Exported file will contain sensitive API keys. Store securely!',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  value: _includeApiKeys,
                  onChanged: (v) => setState(() => _includeApiKeys = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
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
                const Text('Select a previously exported JSON file to restore all settings. API keys will be imported if included in the export.',
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
