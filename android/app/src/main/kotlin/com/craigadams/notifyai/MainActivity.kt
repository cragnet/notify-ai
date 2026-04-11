package com.craigadams.notifyai

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.craigadams.notifyai/permissions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" ->
                    result.success(isNotificationListenerEnabled())

                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings()
                    result.success(null)
                }

                "isUsageStatsPermissionGranted" ->
                    result.success(isUsageStatsPermissionGranted())

                "openUsageStatsSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }

                "isBatteryOptimizationIgnored" ->
                    result.success(isBatteryOptimizationIgnored())

                "requestIgnoreBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization()
                    result.success(null)
                }

                "getInstalledApps" ->
                    result.success(getInstalledApps())

                "isGeminiNanoAvailable" ->
                    result.success(isGeminiNanoAvailable())

                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(packageName)
    }

    private fun openNotificationListenerSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        } else {
            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
        }
        startActivity(intent)
    }

    private fun isUsageStatsPermissionGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimization() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val appMap = mutableMapOf<String, String>() // packageName -> appName

        // Source 1: getInstalledPackages — primary source
        try {
            pm.getInstalledPackages(0).forEach { pkg ->
                try {
                    val appInfo = pkg.applicationInfo ?: return@forEach
                    val label = pm.getApplicationLabel(appInfo).toString()
                    appMap[pkg.packageName] = label
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}

        // Source 2: getInstalledApplications — catches anything missed above
        try {
            pm.getInstalledApplications(0).forEach { app ->
                if (!appMap.containsKey(app.packageName)) {
                    try {
                        appMap[app.packageName] = pm.getApplicationLabel(app).toString()
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        // Source 3: UsageStatsManager — backup for any app that has been used
        // but wasn't visible to the package manager queries above
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            val now = System.currentTimeMillis()
            // Look back 6 months to catch everything that's been used
            val sixMonthsAgo = now - (180L * 24 * 60 * 60 * 1000)
            val usageStats = usm.queryUsageStats(
                android.app.usage.UsageStatsManager.INTERVAL_BEST,
                sixMonthsAgo,
                now
            )
            usageStats?.forEach { stat ->
                val pkg = stat.packageName
                if (!appMap.containsKey(pkg)) {
                    try {
                        val appInfo = pm.getApplicationInfo(pkg, 0)
                        val label = pm.getApplicationLabel(appInfo).toString()
                        appMap[pkg] = label
                    } catch (_: Exception) {
                        // Can't get label — use package name as fallback label
                        appMap[pkg] = pkg.split(".").last()
                            .replaceFirstChar { it.uppercase() }
                    }
                }
            }
        } catch (_: Exception) {}

        return appMap.entries
            .map { mapOf("packageName" to it.key, "appName" to it.value) }
            .sortedBy { it["appName"]?.lowercase() }
    }

    private fun isGeminiNanoAvailable(): Boolean {
        // Check for Google AI Edge / Gemini Nano on-device
        return try {
            val pm = packageManager
            // Gemini Nano is available via Google Play Services AI Core
            pm.getPackageInfo("com.google.android.aicore", 0)
            true
        } catch (e: Exception) {
            false
        }
    }
}
