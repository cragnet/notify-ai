import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../services/permissions_service.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool setupComplete = false;
  bool serviceEnabled = true;

  String aiProvider = 'ollama';
  String backupProvider1 = '';
  String backupProvider2 = '';

  // WiFi-based provider switching
  String wifiSsid1 = '';
  String wifiProvider1 = '';
  String wifiSsid2 = '';
  String wifiProvider2 = '';

  Map<String, String> providerModels = {};
  Map<String, String> providerBaseUrls = {};
  Map<String, String> apiKeys = {};

  int summaryLength = 2;
  int notificationThreshold = 2;
  int summaryCooldownMs = 30000;
  bool dismissOnAppUsage = true;
  bool retainOriginalActions = true;
  String customPrompt = '';

  Map<String, int> appCooldowns = {}; // packageName -> custom cooldown in ms (0 = use global)

  // Theme: 0 = dark, 1 = light, 2 = system
  int themeMode = 0;

  // Digest settings
  bool digestEnabled = false;
  String digestScheduleType = 'fixed_times'; // fixed_times, interval, daily, weekly
  int digestIntervalMinutes = 120; // for interval type
  String digestDailyTime = '09:00'; // for daily type
  int digestWeeklyDay = 1; // 0=Sun..6=Sat, default Mon
  String digestWeeklyTime = '09:00'; // for weekly type
  String digestAppFilter = 'all'; // all, include_only, exclude
  List<String> digestAppList = []; // packages to include/exclude
  String digestPrompt = ''; // custom prompt for digest summaries
  List<String> digestTimes = [];

  // Default digest prompt template
  static const String defaultDigestPrompt = '''You are generating a periodic digest summary of notifications accumulated over time.

Context: These notifications may span multiple apps and conversations. Group related items, prioritise urgent or actionable messages, and provide a coherent overview.

App: {app_name}
Notifications:
{notifications}
Total count: {count}

Provide a well-structured digest. Highlight time-sensitive items and anything requiring action. Use clear sections if multiple topics are involved.''';

  Set<String> enabledApps = {};
  Map<String, int?> notificationColors = {}; // packageName -> color value
  Map<String, int> appThresholds = {}; // packageName -> custom threshold (null means use global)

  // Default prompt template
  static const String defaultPrompt = '''Summarize the following notifications concisely.

Provide bullet points highlighting the key information.
Be brief but informative.''';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    setupComplete = _prefs.getBool('setup_complete') ?? false;
    serviceEnabled = _prefs.getBool('service_enabled') ?? true;
    aiProvider = _prefs.getString('ai_provider') ?? 'ollama';
    backupProvider1 = _prefs.getString('backup_provider_1') ?? '';
    backupProvider2 = _prefs.getString('backup_provider_2') ?? '';
    wifiSsid1 = _prefs.getString('wifi_ssid_1') ?? '';
    wifiProvider1 = _prefs.getString('wifi_provider_1') ?? '';
    wifiSsid2 = _prefs.getString('wifi_ssid_2') ?? '';
    wifiProvider2 = _prefs.getString('wifi_provider_2') ?? '';
    summaryLength = _prefs.getInt('summary_length') ?? 2;
    notificationThreshold = _prefs.getInt('notification_threshold') ?? 2;
    summaryCooldownMs = _prefs.getInt('summary_cooldown_ms') ?? 30000;
    dismissOnAppUsage = _prefs.getBool('dismiss_on_app_usage') ?? true;
    retainOriginalActions = _prefs.getBool('retain_original_actions') ?? true;
    customPrompt = _prefs.getString('custom_prompt') ?? defaultPrompt;
    themeMode = _prefs.getInt('theme_mode') ?? 0;
    digestEnabled = _prefs.getBool('digest_enabled') ?? false;
    digestScheduleType = _prefs.getString('digest_schedule_type') ?? 'fixed_times';
    digestIntervalMinutes = _prefs.getInt('digest_interval_minutes') ?? 120;
    digestDailyTime = _prefs.getString('digest_daily_time') ?? '09:00';
    digestWeeklyDay = _prefs.getInt('digest_weekly_day') ?? 1;
    digestWeeklyTime = _prefs.getString('digest_weekly_time') ?? '09:00';
    digestAppFilter = _prefs.getString('digest_app_filter') ?? 'all';
    digestAppList = _prefs.getStringList('digest_app_list') ?? [];
    digestPrompt = _prefs.getString('digest_prompt') ?? '';
    digestTimes = _prefs.getStringList('digest_times') ?? [];
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

    // Load per-app thresholds
    final thresholdsJson = _prefs.getString('app_thresholds');
    if (thresholdsJson != null) {
      try {
        final thresholdsMap = jsonDecode(thresholdsJson) as Map<String, dynamic>;
        appThresholds = thresholdsMap.map((key, value) =>
          MapEntry(key, value as int));
      } catch (_) {}
    }

    // Load per-app cooldowns
    final cooldownsJson = _prefs.getString('app_cooldowns');
    if (cooldownsJson != null) {
      try {
        final cooldownsMap = jsonDecode(cooldownsJson) as Map<String, dynamic>;
        appCooldowns = cooldownsMap.map((key, value) =>
          MapEntry(key, value as int));
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

  Future<void> setBackupProvider1(String provider) async {
    backupProvider1 = provider;
    await _prefs.setString('backup_provider_1', provider);
    notifyListeners();
  }

  Future<void> setBackupProvider2(String provider) async {
    backupProvider2 = provider;
    await _prefs.setString('backup_provider_2', provider);
    notifyListeners();
  }

  Future<void> setWifiSsid1(String ssid) async {
    wifiSsid1 = ssid;
    await _prefs.setString('wifi_ssid_1', ssid);
    notifyListeners();
  }

  Future<void> setWifiProvider1(String provider) async {
    wifiProvider1 = provider;
    await _prefs.setString('wifi_provider_1', provider);
    notifyListeners();
  }

  Future<void> setWifiSsid2(String ssid) async {
    wifiSsid2 = ssid;
    await _prefs.setString('wifi_ssid_2', ssid);
    notifyListeners();
  }

  Future<void> setWifiProvider2(String provider) async {
    wifiProvider2 = provider;
    await _prefs.setString('wifi_provider_2', provider);
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

  Future<void> setSummaryCooldownMs(int v) async {
    summaryCooldownMs = v;
    await _prefs.setInt('summary_cooldown_ms', v);
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

  Future<void> setThemeMode(int v) async {
    themeMode = v;
    await _prefs.setInt('theme_mode', v);
    notifyListeners();
  }

  Future<void> setDigestEnabled(bool v) async {
    digestEnabled = v;
    await _prefs.setBool('digest_enabled', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestScheduleType(String v) async {
    digestScheduleType = v;
    await _prefs.setString('digest_schedule_type', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestIntervalMinutes(int v) async {
    digestIntervalMinutes = v;
    await _prefs.setInt('digest_interval_minutes', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestDailyTime(String v) async {
    digestDailyTime = v;
    await _prefs.setString('digest_daily_time', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestWeeklyDay(int v) async {
    digestWeeklyDay = v;
    await _prefs.setInt('digest_weekly_day', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestWeeklyTime(String v) async {
    digestWeeklyTime = v;
    await _prefs.setString('digest_weekly_time', v);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> setDigestAppFilter(String v) async {
    digestAppFilter = v;
    await _prefs.setString('digest_app_filter', v);
    notifyListeners();
  }

  Future<void> setDigestAppList(List<String> v) async {
    digestAppList = List.from(v);
    await _prefs.setStringList('digest_app_list', digestAppList);
    notifyListeners();
  }

  Future<void> toggleDigestApp(String packageName) async {
    if (digestAppList.contains(packageName)) {
      digestAppList.remove(packageName);
    } else {
      digestAppList.add(packageName);
    }
    await _prefs.setStringList('digest_app_list', digestAppList);
    notifyListeners();
  }

  Future<void> setDigestPrompt(String v) async {
    digestPrompt = v;
    await _prefs.setString('digest_prompt', v);
    notifyListeners();
  }

  String getDigestPrompt() => digestPrompt.isNotEmpty ? digestPrompt : defaultDigestPrompt;

  Future<void> setDigestTimes(List<String> times) async {
    digestTimes = List.from(times);
    await _prefs.setStringList('digest_times', digestTimes);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

  Future<void> addDigestTime(String time) async {
    if (!digestTimes.contains(time)) {
      digestTimes.add(time);
      digestTimes.sort();
      await _prefs.setStringList('digest_times', digestTimes);
      notifyListeners();
      PermissionsService.rescheduleDigestAlarms();
    }
  }

  Future<void> removeDigestTime(String time) async {
    digestTimes.remove(time);
    await _prefs.setStringList('digest_times', digestTimes);
    notifyListeners();
    PermissionsService.rescheduleDigestAlarms();
  }

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

  // Per-app threshold methods
  int? getAppThreshold(String packageName) {
    return appThresholds[packageName];
  }

  Future<void> setAppThreshold(String packageName, int? threshold) async {
    if (threshold == null) {
      appThresholds.remove(packageName);
    } else {
      appThresholds[packageName] = threshold;
    }
    await _saveAppThresholds();
    notifyListeners();
  }

  Future<void> _saveAppThresholds() async {
    await _prefs.setString('app_thresholds', jsonEncode(appThresholds));
  }

  // Per-app cooldown methods
  int getAppCooldown(String packageName) {
    return appCooldowns[packageName] ?? 0;
  }

  Future<void> setAppCooldown(String packageName, int cooldownMs) async {
    if (cooldownMs <= 0) {
      appCooldowns.remove(packageName);
    } else {
      appCooldowns[packageName] = cooldownMs;
    }
    await _saveAppCooldowns();
    notifyListeners();
  }

  Future<void> _saveAppCooldowns() async {
    await _prefs.setString('app_cooldowns', jsonEncode(appCooldowns));
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
