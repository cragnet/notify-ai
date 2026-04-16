import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool setupComplete = false;
  bool serviceEnabled = true;

  String aiProvider = 'ollama';
  Map<String, String> providerModels = {};
  Map<String, String> providerBaseUrls = {};
  Map<String, String> apiKeys = {};

  int summaryLength = 2;
  int notificationThreshold = 2;
  bool dismissOnAppUsage = true;
  bool retainOriginalActions = true;
  String customPrompt = '';

  Set<String> enabledApps = {};
  Map<String, int?> notificationColors = {}; // packageName -> color value

  // Default prompt template
  static const String defaultPrompt = '''Summarize the following notifications concisely.

Provide bullet points highlighting the key information.
Be brief but informative.''';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    setupComplete = _prefs.getBool('setup_complete') ?? false;
    serviceEnabled = _prefs.getBool('service_enabled') ?? true;
    aiProvider = _prefs.getString('ai_provider') ?? 'ollama';
    summaryLength = _prefs.getInt('summary_length') ?? 2;
    notificationThreshold = _prefs.getInt('notification_threshold') ?? 2;
    dismissOnAppUsage = _prefs.getBool('dismiss_on_app_usage') ?? true;
    retainOriginalActions = _prefs.getBool('retain_original_actions') ?? true;
    customPrompt = _prefs.getString('custom_prompt') ?? defaultPrompt;
    enabledApps = (_prefs.getStringList('enabled_apps') ?? []).toSet();

    // Load notification colors
    final colorsJson = _prefs.getString('notification_colors');
    if (colorsJson != null) {
      try {
        final colorsMap = jsonDecode(colorsJson) as Map<String, dynamic>;
        notificationColors = colorsMap.map((key, value) =>
          MapEntry(key, value != null ? value as int : null));
      } catch (_) {}
    }

    for (final p in ['claude', 'openai', 'ollama', 'openrouter', 'gemini', 'gemini_nano', 'local']) {
      final model = _prefs.getString('model_$p');
      if (model != null) providerModels[p] = model;
      final url = _prefs.getString('base_url_$p');
      if (url != null) providerBaseUrls[p] = url;
    }

    for (final p in ['claude', 'openai', 'openrouter', 'gemini', 'ollama', 'local']) {
      try {
        final key = await _secure.read(key: 'api_key_$p');
        if (key != null && key.isNotEmpty) apiKeys[p] = key;
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> completeSetup() async {
    setupComplete = true;
    await _prefs.setBool('setup_complete', true);
    notifyListeners();
  }

  Future<void> setAiProvider(String provider) async {
    aiProvider = provider;
    await _prefs.setString('ai_provider', provider);
    notifyListeners();
  }

  Future<void> setApiKey(String provider, String key) async {
    if (key.isEmpty) {
      apiKeys.remove(provider);
      await _secure.delete(key: 'api_key_$provider');
      await _prefs.remove('api_key_$provider');
    } else {
      apiKeys[provider] = key;
      await _secure.write(key: 'api_key_$provider', value: key);
      await _prefs.setString('api_key_$provider', key);
    }
    notifyListeners();
  }

  String getApiKey(String provider) => apiKeys[provider] ?? '';

  Future<void> setModel(String provider, String model) async {
    providerModels[provider] = model;
    await _prefs.setString('model_$provider', model);
    notifyListeners();
  }

  String getModel(String provider) {
    if (providerModels.containsKey(provider) && providerModels[provider]!.isNotEmpty) {
      return providerModels[provider]!;
    }
    // No hardcoded defaults — user must enter model name
    return '';
  }

  Future<void> setBaseUrl(String provider, String url) async {
    providerBaseUrls[provider] = url;
    await _prefs.setString('base_url_$provider', url);
    notifyListeners();
  }

  String getBaseUrl(String provider) {
    if (providerBaseUrls.containsKey(provider) && providerBaseUrls[provider]!.isNotEmpty) {
      return providerBaseUrls[provider]!;
    }
    // Only Claude and OpenAI have sensible defaults — everything else blank
    switch (provider) {
      case 'claude': return 'https://api.anthropic.com';
      case 'openai': return 'https://api.openai.com';
      case 'openrouter': return 'https://openrouter.ai';
      default: return '';
    }
  }

  Future<void> setSummaryLength(int v) async {
    summaryLength = v;
    await _prefs.setInt('summary_length', v);
    notifyListeners();
  }

  Future<void> setNotificationThreshold(int v) async {
    notificationThreshold = v;
    await _prefs.setInt('notification_threshold', v);
    notifyListeners();
  }

  Future<void> setDismissOnAppUsage(bool v) async {
    dismissOnAppUsage = v;
    await _prefs.setBool('dismiss_on_app_usage', v);
    notifyListeners();
  }

  Future<void> setRetainOriginalActions(bool v) async {
    retainOriginalActions = v;
    await _prefs.setBool('retain_original_actions', v);
    notifyListeners();
  }

  Future<void> setCustomPrompt(String prompt) async {
    customPrompt = prompt;
    await _prefs.setString('custom_prompt', prompt);
    notifyListeners();
  }

  String getCustomPrompt() => customPrompt.isNotEmpty ? customPrompt : defaultPrompt;

  Future<void> setServiceEnabled(bool v) async {
    serviceEnabled = v;
    await _prefs.setBool('service_enabled', v);
    notifyListeners();
  }

  Future<void> toggleApp(String packageName) async {
    if (enabledApps.contains(packageName)) {
      enabledApps.remove(packageName);
    } else {
      enabledApps.add(packageName);
    }
    await _saveEnabledApps();
    notifyListeners();
  }

  Future<void> setEnabledApps(Set<String> apps) async {
    enabledApps = Set.from(apps);
    await _saveEnabledApps();
    notifyListeners();
  }

  Future<void> _saveEnabledApps() async {
    final list = enabledApps.toList();
    await _prefs.setStringList('enabled_apps', list);
    await _prefs.setStringList('enabled_apps_set', list);
    await _prefs.reload();
    // ignore: avoid_print
    print('NotifyAI: saved enabled_apps_set: $list');
    notifyListeners();
  }

  // Notification color methods
  int? getNotificationColor(String packageName) {
    return notificationColors[packageName];
  }

  Future<void> setNotificationColor(String packageName, int? color) async {
    if (color == null) {
      notificationColors.remove(packageName);
    } else {
      notificationColors[packageName] = color;
    }
    await _saveNotificationColors();
    notifyListeners();
  }

  Future<void> _saveNotificationColors() async {
    final colorsMap = notificationColors.map((key, value) =>
      MapEntry(key, value));
    await _prefs.setString('notification_colors', jsonEncode(colorsMap));
  }

  // Method to get API keys for export
  Map<String, String> getApiKeysForExport({bool includeKeys = false}) {
    if (!includeKeys) return {};
    return Map.from(apiKeys);
  }

  Future<void> importApiKey(String provider, String key) async {
    if (key.isNotEmpty) {
      await setApiKey(provider, key);
    }
  }
}
