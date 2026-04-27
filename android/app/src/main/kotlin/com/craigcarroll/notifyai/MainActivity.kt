package com.craigcarroll.notifyai

import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.service.notification.NotificationListenerService
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.craigcarroll.notifyai/permissions"

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

                "getAppIcon" -> {
                    val pkg = call.argument<String>("packageName")
                    if (pkg != null) result.success(getAppIcon(pkg))
                    else result.error("INVALID_ARG", "packageName required", null)
                }

                "isGeminiNanoAvailable" ->
                    result.success(isGeminiNanoAvailable())

                "rescheduleDigestAlarms" -> {
                    val service = NotificationService.getInstance()
                    if (service != null) {
                        service.scheduleDigestAlarms()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                "restartNotificationListener" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        NotificationListenerService.requestRebind(
                            android.content.ComponentName(this, NotificationService::class.java)
                        )
                    }
                    result.success(true)
                }

                "sendTestNotification" -> {
                    val count = call.argument<Int>("count") ?: 1
                    val appPackage = call.argument<String>("packageName") ?: "com.test.app"
                    val appName = call.argument<String>("appName") ?: "Test App"
                    val testType = call.argument<String>("testType") ?: "single" // single, multi_conversation, duplicates
                    sendTestNotifications(count, appPackage, appName, testType)
                    result.success(null)
                }

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

    private fun getAppIcon(packageName: String): String? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val size = 48
            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val bmp = Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(1),
                    drawable.intrinsicHeight.coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888
                )
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            val scaled = Bitmap.createScaledBitmap(bitmap, size, size, true)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.PNG, 90, out)
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) { null }
    }

    private fun isGeminiNanoAvailable(): Boolean {
        return try {
            runBlocking {
                val generation = com.google.mlkit.genai.prompt.Generation.getClient()
                val status = generation.checkStatus()
                status == com.google.mlkit.genai.common.FeatureStatus.AVAILABLE ||
                    status == com.google.mlkit.genai.common.FeatureStatus.DOWNLOADABLE
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun sendTestNotifications(count: Int, packageName: String, appName: String, testType: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channelId = "notify_ai_test"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                android.app.NotificationChannel(channelId, "Test Notifications", android.app.NotificationManager.IMPORTANCE_HIGH)
            )
        }

        when (testType) {
            "duplicates" -> sendDuplicateTestNotifications(count, nm, channelId, packageName, appName)
            "multi_conversation" -> sendMultiConversationTestNotifications(count, nm, channelId, packageName, appName)
            else -> sendSingleConversationTestNotifications(count, nm, channelId, packageName, appName)
        }
    }

    // Track test notification IDs so service can cancel them after summarising
    private val testNotificationIds = mutableListOf<Int>()

    private fun sendSingleConversationTestNotifications(count: Int, nm: android.app.NotificationManager, channelId: String, packageName: String, appName: String) {
        // All notifications from same sender/conversation
        val sender = listOf("Alice", "Bob", "Carol").random()
        val conversation = "General Chat"
        testNotificationIds.clear()

        for (i in 1..count) {
            val title = "$conversation: ~ $sender"
            val text = "Test message $i: Hey, just testing the notification summary feature!"

            // Use consistent ID that service can use to replace this notification
            val notifId = "${packageName}:test:${System.currentTimeMillis()}:$i".hashCode()
            testNotificationIds.add(notifId)

            val builder = createTestNotificationBuilder(nm, channelId)
            builder.setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .setGroup("test_group_$packageName")

            nm.notify(notifId, builder.build())

            // Also inject into NotificationService for logging/processing
            NotificationService.injectTestNotification(packageName, title, text, conversation, testNotificationIds)

            Thread.sleep(100)
        }
    }

    private fun sendMultiConversationTestNotifications(count: Int, nm: android.app.NotificationManager, channelId: String, packageName: String, appName: String) {
        // Notifications from different conversations
        val conversations = listOf(
            "Family Group" to listOf("Mom", "Dad", "Sister"),
            "Work Chat" to listOf("Boss", "Colleague", "HR"),
            "Friends" to listOf("Bestie", "Gym Buddy", "Gamer Friend")
        )
        testNotificationIds.clear()

        for (i in 1..count) {
            val (conversation, senders) = conversations[i % conversations.size]
            val sender = senders.random()
            val title = "$conversation: ~ $sender"
            val text = "Message from $conversation - ${sender}: Test notification $i for multi-conversation testing"
            val builder = createTestNotificationBuilder(nm, channelId)

            val notifId = "${packageName}:test:${System.currentTimeMillis()}:$i".hashCode()
            testNotificationIds.add(notifId)

            builder.setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .setGroup("test_group_$packageName")

            nm.notify(notifId, builder.build())

            // Also inject into NotificationService for logging/processing
            NotificationService.injectTestNotification(packageName, title, text, conversation, testNotificationIds)

            Thread.sleep(100)
        }
    }

    private fun sendDuplicateTestNotifications(count: Int, nm: android.app.NotificationManager, channelId: String, packageName: String, appName: String) {
        // Send same message multiple times (to test AI deduplication)
        val sender = "Test User"
        val conversation = "Test Chat"
        val duplicateMessage = "This is the exact same message sent multiple times to test AI deduplication"
        testNotificationIds.clear()

        for (i in 1..count) {
            val title = "$conversation: ~ $sender"
            val builder = createTestNotificationBuilder(nm, channelId)
            builder.setContentTitle(title)
                .setContentText(duplicateMessage)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .setGroup("test_group_$packageName")

            val notifId = "${packageName}:test:${System.currentTimeMillis()}:$i".hashCode()
            testNotificationIds.add(notifId)

            nm.notify(notifId, builder.build())

            // Also inject into NotificationService for logging/processing
            NotificationService.injectTestNotification(packageName, title, duplicateMessage, conversation, testNotificationIds)

            Thread.sleep(100)
        }
    }

    private fun createTestNotificationBuilder(nm: android.app.NotificationManager, channelId: String): android.app.Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
    }
}
