import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  static const _ch = MethodChannel('com.craigcarroll.notifyai/permissions');

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
  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final result = await _ch.invokeMethod('getAppIcon', {'packageName': packageName});
      if (result == null) return null;
      return base64Decode(result as String);
    } catch (_) { return null; }
  }

  static Future<bool> isGeminiNanoAvailable() async {
    try { return await _ch.invokeMethod('isGeminiNanoAvailable') ?? false; } catch (_) { return false; }
  }

  static Future<bool> rescheduleDigestAlarms() async {
    try { return await _ch.invokeMethod('rescheduleDigestAlarms') ?? false; } catch (_) { return false; }
  }

  static Future<bool> restartNotificationListener() async {
    try { return await _ch.invokeMethod('restartNotificationListener') ?? false; } catch (_) { return false; }
  }

  // POST_NOTIFICATIONS permission (Android 13+)
  static Future<bool> isPostNotificationsGranted() async {
    if (await Permission.notification.isGranted) return true;
    // On Android < 13 notifications are always allowed
    return true;
  }

  static Future<bool> requestPostNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
