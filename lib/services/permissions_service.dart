import 'package:flutter/services.dart';

class PermissionsService {
  static const _ch = MethodChannel('com.craigadams.notifyai/permissions');

  static Future<bool> isNotificationListenerEnabled() async {
    try { return await _ch.invokeMethod('isNotificationListenerEnabled') ?? false; } catch (_) { return false; }
  }
  static Future<void> openNotificationListenerSettings() async {
    try { await _ch.invokeMethod('openNotificationListenerSettings'); } catch (_) {}
  }
  static Future<bool> isUsageStatsPermissionGranted() async {
    try { return await _ch.invokeMethod('isUsageStatsPermissionGranted') ?? false; } catch (_) { return false; }
  }
  static Future<void> openUsageStatsSettings() async {
    try { await _ch.invokeMethod('openUsageStatsSettings'); } catch (_) {}
  }
  static Future<bool> isBatteryOptimizationIgnored() async {
    try { return await _ch.invokeMethod('isBatteryOptimizationIgnored') ?? false; } catch (_) { return false; }
  }
  static Future<void> requestIgnoreBatteryOptimization() async {
    try { await _ch.invokeMethod('requestIgnoreBatteryOptimization'); } catch (_) {}
  }
  static Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final result = await _ch.invokeMethod('getInstalledApps');
      if (result == null) return [];
      return (result as List).map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) { return []; }
  }
  static Future<bool> isGeminiNanoAvailable() async {
    try { return await _ch.invokeMethod('isGeminiNanoAvailable') ?? false; } catch (_) { return false; }
  }
}
