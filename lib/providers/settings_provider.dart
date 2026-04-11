import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool setupComplete = false;
  bool serviceEnabled = true;

  String aiProvider = 'claude';
  Map<String, String> providerModels = {};
  Map<String, String> providerBaseUrls = {};
  Map<String, String> apiKeys = {};

  int summaryLength = 2;
  int notificationThreshold = 2;
  bool dismissOnAppUsage = true;
  bool retainOriginalActions = true;

  Set<String> enabledApps = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    setupComplete = _prefs.getBool('setup_complete') ?? false;
    serviceEnabled = _prefs.getBool('service_enabled') ?? true;
    aiProvider = _prefs.getString('ai_provider') ?? 'claude';
    summaryLength = _prefs.getInt('summary_length') ?? 2;
    notificationThreshold = _prefs.getInt('notification_threshold') ?? 2;
    dismissOnAppUsage = _prefs.getBool('dismiss_on_app_usage') ?? true;
    retainOriginalActions = _prefs.getBool('retain_original_actions') ?? true;
    enabledApps = (_prefs.getStringList('enabled_apps') ?? []).toSet();

    // Load per-provider models and base URLs
    for (final p in ['claude', 'openai', 'ollama', 'openrouter', 'gemini', 'gemini_nano']) {
      final model = _prefs.getString('model_$p');
      if (model != null) providerModels[p] = model;
      final url = _prefs.getString('base_url_$p');
      if (url != null) providerBaseUrls[p] = url;
    }

    // Load API keys from encrypted storage
    for (final p in ['claude', 'openai', 'openrouter', 'gemini']) {
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

  // ── Provider / model / key ─────────────────────────────────────────────────

  Future<void> setAiProvider(String provider) async {
    aiProvider = provider;
    await _prefs.setString('ai_provider', provider);
    notifyListeners();
  }

  Future<void> setApiKey(String provider, String key) async {
    apiKeys[provider] = key;
    // Encrypted store
    await _secure.write(key: 'api_key_$provider', value: key);
    // Also mirror to shared prefs so native Kotlin service can read it
    await _prefs.setString('api_key_$provider', key);
    notifyListeners();
  }

  String getApiKey(String provider) => apiKeys[provider] ?? '';

  Future<void> setModel(String provider, String model) async {
    providerModels[provider] = model;
    await _prefs.setString('model_$provider', model);
    notifyListeners();
  }

  String getModel(String provider) {
    if (providerModels.containsKey(provider)) return providerModels[provider]!;
    const defaults = {
      'claude': 'claude-haiku-4-5-20251001',
      'openai': 'gpt-4o-mini',
      'ollama': 'llama3.2:3b',
      'openrouter': 'anthropic/claude-haiku-4-5',
      'gemini': 'gemini-2.0-flash',
      'gemini_nano': 'gemini-nano',
    };
    return defaults[provider] ?? '';
  }

  Future<void> setBaseUrl(String provider, String url) async {
    providerBaseUrls[provider] = url;
    await _prefs.setString('base_url_$provider', url);
    notifyListeners();
  }

  String getBaseUrl(String provider) {
    if (providerBaseUrls.containsKey(provider)) return providerBaseUrls[provider]!;
    const defaults = {
      'claude': 'https://api.anthropic.com',
      'openai': 'https://api.openai.com',
      'ollama': 'http://10.0.1.33:11434',
      'openrouter': 'https://openrouter.ai',
    };
    return defaults[provider] ?? '';
  }

  // ── Global settings ────────────────────────────────────────────────────────

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

  Future<void> setServiceEnabled(bool v) async {
    serviceEnabled = v;
    await _prefs.setBool('service_enabled', v);
    notifyListeners();
  }

  // ── App selection ──────────────────────────────────────────────────────────

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
    enabledApps = apps;
    await _saveEnabledApps();
    notifyListeners();
  }

  Future<void> _saveEnabledApps() async {
    final list = enabledApps.toList();
    await _prefs.setStringList('enabled_apps', list);
    // Also save as a StringSet for the native service
    await _prefs.setStringSet('enabled_apps_set', enabledApps);
  }
}

// Extension to support setStringSet on SharedPreferences
extension SharedPreferencesExt on SharedPreferences {
  Future<bool> setStringSet(String key, Set<String> value) {
    return setStringList(key, value.toList());
  }
}
