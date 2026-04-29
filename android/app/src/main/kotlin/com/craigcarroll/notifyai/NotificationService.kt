package com.craigcarroll.notifyai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.security.MessageDigest

class NotificationService : NotificationListenerService() {

    private val TAG = "NotifyAI"
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        private var instance: NotificationService? = null

        // Hard limits to prevent unbounded in-memory growth
        private const val MAX_BUFFERED_PER_APP = 50
        private const val MAX_BUFFERED_GLOBAL = 200
        private const val MAX_BUFFER_AGE_MS = 86400000L // 24 hours

        // Map for wrapping original notification actions so we can cancel our summary
        // when the user taps an action on it.
        val actionMap = mutableMapOf<String, PendingIntent>()

        @JvmStatic
        fun getInstance(): NotificationService? = instance

        @JvmStatic
        fun injectTestNotification(pkg: String, title: String, text: String, conversationId: String?, originalNotificationIds: List<Int>? = null) {
            val service = instance
            if (service != null) {
                service.log("info", "[TEST] Injecting test notification: pkg=$pkg, title=$title, text=$text")
                service.handleTestNotification(pkg, title, text, conversationId, originalNotificationIds)
            } else {
                Log.w("NotifyAI", "[TEST] Cannot inject - service not running")
            }
        }
    }

    data class NotificationItem(
        val title: String,
        val text: String,
        val actions: List<Notification.Action>,
        val sbnKey: String,
        val imageBase64: String? = null,
        val timestamp: Long = System.currentTimeMillis(),
        val conversationId: String? = null,
        val contentHash: String = ""  // Hash of title+text for duplicate detection
    ) {
        // Helper to compute content hash
        fun computeHash(): String {
            val content = "${title.lowercase().trim()}:${text.lowercase().trim()}"
            return MessageDigest.getInstance("MD5").digest(content.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }

        fun toJson(): JSONObject {
            val actionsJson = JSONArray()
            actions.forEach { action ->
                actionsJson.put(JSONObject().apply {
                    put("title", action.title?.toString() ?: "")
                    put("actionIntent", action.actionIntent?.toString() ?: "")
                })
            }
            return JSONObject().apply {
                put("title", title)
                put("text", text)
                put("sbnKey", sbnKey)
                put("imageBase64", imageBase64 ?: "")
                put("timestamp", timestamp)
                put("conversationId", conversationId ?: "")
                put("contentHash", contentHash)
                put("actions", actionsJson)
            }
        }

        companion object {
            fun fromJson(json: JSONObject): NotificationItem {
                val actionsList = mutableListOf<Notification.Action>()
                try {
                    val arr = json.getJSONArray("actions")
                    for (i in 0 until arr.length()) {
                        val a = arr.getJSONObject(i)
                        actionsList.add(Notification.Action.Builder(
                            android.R.drawable.ic_menu_send,
                            a.optString("title", "Action"),
                            null
                        ).build())
                    }
                } catch (_: Exception) {}
                return NotificationItem(
                    title = json.optString("title", ""),
                    text = json.optString("text", ""),
                    actions = actionsList,
                    sbnKey = json.optString("sbnKey", ""),
                    imageBase64 = json.optString("imageBase64", "").takeIf { it.isNotEmpty() },
                    timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                    conversationId = json.optString("conversationId", "").takeIf { it.isNotEmpty() },
                    contentHash = json.optString("contentHash", "")
                )
            }
        }
    }

    data class NotificationGroup(
        val notifications: MutableList<NotificationItem> = mutableListOf(),
        var summary: String? = null,
        var summaryTimestamp: Long = 0,
        var notificationColor: Int? = null,
        var packageName: String? = null,
        var previousConversationIds: Set<String?> = emptySet()
    ) {
        // Track notifications per conversation for per-conversation thresholds
        val conversationBuffers: MutableMap<String?, MutableList<NotificationItem>> = mutableMapOf()

        // Track notification IDs per conversation to update existing summaries
        val conversationNotificationIds: MutableMap<String?, Int> = mutableMapOf()

        // Track keys of notifications that contributed to the current summary so we
        // can cancel the summary when all originals are dismissed by the user.
        val lastSummarizedKeys: MutableSet<String> = mutableSetOf()
        val dismissedSummarizedKeys: MutableSet<String> = mutableSetOf()

        fun getOrCreateNotificationId(conversationId: String?): Int {
            return conversationNotificationIds.getOrPut(conversationId) {
                // Generate consistent ID based on package + conversation
                "${packageName}:conv:${conversationId}".hashCode()
            }
        }

        fun getConversationCount(conversationId: String?): Int {
            return conversationBuffers[conversationId]?.size ?: 0
        }

        fun addToConversation(item: NotificationItem) {
            val convId = item.conversationId
            conversationBuffers.getOrPut(convId) { mutableListOf() }.add(item)
        }

        fun removeFromConversation(conversationId: String?, sbnKey: String): Boolean {
            val convList = conversationBuffers[conversationId] ?: return false
            val index = convList.indexOfFirst { it.sbnKey == sbnKey }
            if (index >= 0) {
                convList.removeAt(index)
                if (convList.isEmpty()) {
                    conversationBuffers.remove(conversationId)
                }
                return true
            }
            return false
        }

        fun removeNotificationByKey(sbnKey: String): Boolean {
            var removed = false
            val iter = conversationBuffers.iterator()
            while (iter.hasNext()) {
                val entry = iter.next()
                if (entry.value.removeAll { it.sbnKey == sbnKey }) {
                    removed = true
                    if (entry.value.isEmpty()) {
                        iter.remove()
                    }
                }
            }
            if (notifications.removeAll { it.sbnKey == sbnKey }) {
                removed = true
            }
            return removed
        }

        fun getNotificationsForConversation(conversationId: String?): List<NotificationItem> {
            return conversationBuffers[conversationId]?.toList() ?: emptyList()
        }

        fun getAllPendingNotifications(): List<NotificationItem> {
            return conversationBuffers.values.flatMap { it.toList() }
        }

        fun clearProcessedNotifications(processedIds: Set<String>) {
            conversationBuffers.forEach { (convId, list) ->
                list.removeAll { it.sbnKey in processedIds }
            }
            conversationBuffers.entries.removeAll { it.value.isEmpty() }
        }
    }

    // Per-package buffer for grouped notifications
    private val buffer = mutableMapOf<String, NotificationGroup>()
    private val debounce = mutableMapOf<String, Runnable>()
    // Track whether the pending runnable is a short-delay (threshold-met) one.
    // Once threshold is reached we stop rescheduling so rapid notifications
    // cannot push the timer back indefinitely.
    private val debounceShortDelay = mutableMapOf<String, Boolean>()
    private val DEBOUNCE_MS = 3000L
    private val STATUS_NOTIF_ID = "notifyai_status".hashCode()

    // Cooldown to prevent rapid-fire summaries when threshold=1.
    // After posting a summary for a package, block re-summarising the same
    // package for this duration so burst notifications accumulate into one summary.
    private val lastSummaryTime = mutableMapOf<String, Long>()

    // Heartbeat to confirm service is still alive and log when running in background
    private val HEARTBEAT_MS = 300000L // 5 minutes
    private var heartbeatRunnable: Runnable? = null

    // ── SharedPreferences ──────────────────────────────────────────────────────
    private fun sp() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun spBool(key: String, def: Boolean): Boolean {
        return try {
            sp().getBoolean("flutter.$key", def)
        } catch (e: ClassCastException) {
            sp().getString("flutter.$key", null)?.equals("true") ?: def
        }
    }

    private fun spInt(key: String, def: Int): Int {
        return try {
            sp().getInt("flutter.$key", def)
        } catch (e: ClassCastException) {
            try {
                sp().getString("flutter.$key", null)?.toIntOrNull() ?: def
            } catch (_: Exception) { def }
        }
    }

    private fun spStr(key: String, def: String): String =
        sp().getString("flutter.$key", def) ?: def

    // Per-app threshold override. Falls back to global notification_threshold.
    private fun getThresholdForApp(pkg: String): Int {
        val global = spInt("notification_threshold", 2)
        val raw = spStr("app_thresholds", "{}")
        return try {
            val obj = JSONObject(raw)
            if (obj.has(pkg)) obj.getInt(pkg) else global
        } catch (_: Exception) { global }
    }

    // Per-app cooldown override. Falls back to global summary_cooldown_ms.
    private fun getCooldownForApp(pkg: String): Long {
        val global = spInt("summary_cooldown_ms", 30000).toLong()
        val raw = spStr("app_cooldowns", "{}")
        return try {
            val obj = JSONObject(raw)
            if (obj.has(pkg)) obj.getInt(pkg).toLong() else global
        } catch (_: Exception) { global }
    }

    // Flutter encodes StringList as LIST_IDENTIFIER + jsonArray (no separator)
    // LIST_IDENTIFIER = base64("This is the prefix for a string list")
    private fun spList(key: String): List<String> {
        val sp = sp()
        val raw = sp.getString("flutter.$key", null) ?: return emptyList()
        return try {
            val LIST_IDENTIFIER = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHN0cmluZyBsaXN0"
            val jsonStr = when {
                raw.startsWith("[") -> raw                          // plain JSON array
                raw.contains("!") -> raw.substringAfter("!")        // legacy format
                raw.startsWith(LIST_IDENTIFIER) -> raw.substring(LIST_IDENTIFIER.length) // current format
                else -> {
                    log("warn", "spList[$key] unrecognised format: ${raw.take(80)}")
                    return emptyList()
                }
            }
            val arr = JSONArray(jsonStr)
            val result = (0 until arr.length()).map { 
                val item = arr.get(it)
                when (item) {
                    is String -> item
                    is Number -> item.toString()
                    else -> item.toString()
                }
            }
            log("info", "spList[$key] = ${result.size} entries: $result")
            result
        } catch (e: Exception) {
            log("warn", "spList[$key] parse failed: ${e.message} raw=${raw.take(80)}")
            emptyList()
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        log("success", "=== Listener CONNECTED ===")

        // Elevate to foreground service so OS doesn't kill this process
        startForegroundCompat()

        // Start heartbeat to confirm service stays alive in background
        startHeartbeat()

        // Dump raw pref value so we can verify spList parsing
        val rawApps = sp().getString("flutter.enabled_apps_set", null)
        log("info", "raw enabled_apps_set: ${rawApps?.take(120) ?: "(null — no apps saved yet)"}")

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) {
            log("warn", "No apps selected — go to Per-app settings")
            postStatusNotification("Notify AI running — action needed",
                "No apps selected. Open app → Per-app settings.")
        } else {
            log("success", "Monitoring ${selected.size} app(s):")
            selected.forEach { pkg -> log("success", "  ✓ ${appName(pkg)} ($pkg)") }
            postStatusNotification("Notify AI running",
                "Monitoring ${selected.size} app(s)")
        }
        scheduleDigestAlarms()
        processRetryQueue()
    }

    private fun startHeartbeat() {
        heartbeatRunnable?.let { handler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                val selected = spList("enabled_apps_set")
                val bufferCount = buffer.values.sumOf { it.getAllPendingNotifications().size }
                log("info", "HEARTBEAT — service alive, monitoring ${selected.size} app(s), $bufferCount buffered notification(s)")
                handler.postDelayed(this, HEARTBEAT_MS)
            }
        }
        heartbeatRunnable = runnable
        handler.postDelayed(runnable, HEARTBEAT_MS)
        log("info", "Heartbeat started — logging every ${HEARTBEAT_MS / 1000}s")
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let {
            handler.removeCallbacks(it)
            log("info", "Heartbeat stopped")
        }
        heartbeatRunnable = null
    }

    private fun startForegroundCompat() {
        try {
            val channelId = "notify_ai_status"
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(NotificationChannel(channelId,
                    "Notify AI Status", NotificationManager.IMPORTANCE_LOW))
            }
            val notif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, channelId)
            else @Suppress("DEPRECATION") Notification.Builder(this)
            notif.setContentTitle("Notify AI")
                .setContentText("Monitoring notifications")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
            val built = notif.build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(STATUS_NOTIF_ID, built,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(STATUS_NOTIF_ID, built)
            }
            log("info", "startForeground called — service protected")
        } catch (e: Exception) {
            log("warn", "startForeground failed: ${e.message}")
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        stopHeartbeat()
        log("warn", "Listener DISCONNECTED — requesting rebind")
        postStatusNotification("Notify AI reconnecting…", "Service was disconnected — reconnecting automatically")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestRebind(android.content.ComponentName(this, NotificationService::class.java))
        }
    }

    // ── onNotificationPosted ───────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        processRetryQueue()
        try {
            handleNotification(sbn)
        } catch (e: Exception) {
            log("error", "onNotificationPosted crash: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName
            val group = buffer[pkg] ?: return

            val preCount = group.getAllPendingNotifications().size
            log("debug", "onNotificationRemoved for $pkg key=${sbn.key} preCount=$preCount debounce=${debounce.containsKey(pkg)} lastSummarized=${group.lastSummarizedKeys.size}")

            // If this notification contributed to the current summary, track its dismissal.
            // When the user (or the app) has dismissed every original that produced the
            // summary, cancel the summary too so it doesn't linger as stale.
            if (sbn.key in group.lastSummarizedKeys) {
                group.dismissedSummarizedKeys.add(sbn.key)
                if (group.dismissedSummarizedKeys.containsAll(group.lastSummarizedKeys)) {
                    cancelSummaryNotification(pkg)
                    group.lastSummarizedKeys.clear()
                    group.dismissedSummarizedKeys.clear()
                    log("info", "All originals dismissed — cancelled summary for $pkg")
                }
            }

            // If a runnable is pending for this package, the buffer will be cleared
            // when the runnable fires. Removing now would lose message content
            // before the summary can be generated (e.g. WhatsApp stacking).
            if (debounce.containsKey(pkg)) {
                log("info", "Skipped removing ${sbn.key} from buffer — runnable pending for $pkg")
                return
            }

            val removed = group.removeNotificationByKey(sbn.key)
            val postCount = group.getAllPendingNotifications().size
            if (removed) {
                log("info", "Notification DISMISSED for $pkg — removed ${sbn.key} from buffer (system/app cancelled) pre=$preCount post=$postCount")
                // If no notifications remain, also cancel our summary so the user
                // isn't left with a stale summary after dismissing originals
                if (group.getAllPendingNotifications().isEmpty()) {
                    cancelSummaryNotification(pkg)
                }
            } else {
                log("debug", "onNotificationRemoved: key ${sbn.key} not found in buffer for $pkg pre=$preCount post=$postCount")
            }
        } catch (e: Exception) {
            log("error", "onNotificationRemoved crash: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    /** Cancel the summary notification for a package (e.g. when originals are dismissed). */
    private fun cancelSummaryNotification(pkg: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val group = buffer[pkg] ?: return
            val notifId = group.getOrCreateNotificationId("summary")
            nm.cancel(notifId)
            log("info", "Cancelled summary notification for $pkg (id=$notifId)")
        } catch (e: Exception) {
            log("warn", "Failed to cancel summary for $pkg: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Enforce per-app, global, and age-based limits on the notification buffer
     * to prevent unbounded memory growth.
     */
    private fun enforceBufferLimits(targetPkg: String) {
        val now = System.currentTimeMillis()

        // 1. Evict stale notifications by age across all apps
        buffer.values.forEach { group ->
            val staleKeys = mutableSetOf<String>()
            group.conversationBuffers.values.forEach { list ->
                list.filter { now - it.timestamp > MAX_BUFFER_AGE_MS }
                    .forEach { staleKeys.add(it.sbnKey) }
            }
            if (staleKeys.isNotEmpty()) {
                group.clearProcessedNotifications(staleKeys)
                group.lastSummarizedKeys.removeAll(staleKeys)
                log("warn", "Evicted ${staleKeys.size} stale notification(s) from ${group.packageName}")
            }
        }

        // 2. Per-app limit — evict oldest first
        buffer.values.forEach { group ->
            val all = group.getAllPendingNotifications()
            if (all.size > MAX_BUFFERED_PER_APP) {
                val toEvict = all.sortedBy { it.timestamp }
                    .take(all.size - MAX_BUFFERED_PER_APP)
                val evictKeys = toEvict.map { it.sbnKey }.toSet()
                group.clearProcessedNotifications(evictKeys)
                group.lastSummarizedKeys.removeAll(evictKeys)
                log("warn", "Evicted ${evictKeys.size} notification(s) from ${group.packageName} — per-app limit ($MAX_BUFFERED_PER_APP)")
            }
        }

        // 3. Global limit — evict oldest across all apps
        val globalCount = buffer.values.sumOf { it.getAllPendingNotifications().size }
        if (globalCount > MAX_BUFFERED_GLOBAL) {
            val allItems = buffer.values.flatMap { group ->
                group.getAllPendingNotifications().map { group.packageName to it }
            }.sortedBy { it.second.timestamp }
            val toEvict = allItems.take(globalCount - MAX_BUFFERED_GLOBAL)
            toEvict.groupBy { it.first }.forEach { (pkgName, items) ->
                val group = buffer[pkgName] ?: return@forEach
                val evictKeys = items.map { it.second.sbnKey }.toSet()
                group.clearProcessedNotifications(evictKeys)
                group.lastSummarizedKeys.removeAll(evictKeys)
                log("warn", "Evicted ${evictKeys.size} notification(s) from $pkgName — global limit ($MAX_BUFFERED_GLOBAL)")
            }
        }

        // Drop empty groups to free the map entry itself
        buffer.entries.removeAll { it.value.getAllPendingNotifications().isEmpty() }
    }

    private fun handleNotification(sbn: StatusBarNotification) {
        try {
            _handleNotificationInternal(sbn)
        } catch (e: ClassCastException) {
            val stack = e.stackTrace.take(5).joinToString(" ") { "${it.fileName}:${it.lineNumber}" }
            log("error", "ClassCastException: ${e.message} at $stack")
            throw e
        }
    }

    // Handle test notifications injected from MainActivity (for troubleshooting)
    private fun handleTestNotification(pkg: String, title: String, text: String, conversationId: String?, originalNotificationIds: List<Int>? = null) {
        if (!spBool("service_enabled", true)) { log("info", "[TEST] Service disabled"); return }

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) { log("warn", "[TEST] No apps selected"); return }
        if (!selected.contains(pkg)) { log("info", "[TEST] $pkg not selected — skipping"); return }

        log("info", "[TEST] --- Notification from: $pkg ---")

        val name = appName(pkg)

        // Create notification item directly
        val newItem = NotificationItem(
            title = title,
            text = text,
            actions = emptyList(),
            sbnKey = "test_${System.currentTimeMillis()}",
            imageBase64 = null,
            timestamp = System.currentTimeMillis(),
            conversationId = conversationId
        )

        val contentHash = newItem.computeHash()
        val itemWithHash = newItem.copy(contentHash = contentHash)

        val group = buffer.getOrPut(pkg) { NotificationGroup(packageName = pkg) }

        // Remove any stale test notifications from previous runs so they don't
        // combine with real notifications and produce garbage summaries
        group.getAllPendingNotifications()
            .filter { it.sbnKey.startsWith("test_") }
            .forEach {
                group.removeFromConversation(it.conversationId, it.sbnKey)
                group.notifications.removeAll { n -> n.sbnKey == it.sbnKey }
            }

        // Check for content-based duplicates
        val hashDuplicate = group.getAllPendingNotifications().find { it.contentHash == contentHash }
        if (hashDuplicate != null) {
            log("info", "[TEST] Duplicate content detected (hash match) - skipping")
            return
        }

        // Add to buffer
        group.addToConversation(itemWithHash)
        group.notifications.add(itemWithHash)
        enforceBufferLimits(pkg)
        saveHistory(pkg, name, title, text, false)
        recordStat(pkg, intercepted = true, summarised = false)
        log("info", "[TEST] Added test notification to conversation '$conversationId' for $name")

        // Check threshold and trigger
        val threshold = getThresholdForApp(pkg)
        val convCount = group.getConversationCount(conversationId)
        val totalCount = group.getAllPendingNotifications().size

        log("info", "[TEST] Threshold check: conv=$convCount, total=$totalCount, threshold=$threshold")

        // Create runnable to process this app's notifications
        val runnable = Runnable {
            val currentGroup = buffer[pkg] ?: return@Runnable
            val currentThreshold = getThresholdForApp(pkg)
            val allNotifications = currentGroup.getAllPendingNotifications()
            val currentTotal = allNotifications.size

            log("info", "[TEST] RUNNABLE CHECK for $name: total=$currentTotal, threshold=$currentThreshold")

            if (currentTotal < currentThreshold) {
                debounce.remove(pkg)
                log("info", "[TEST] DEFERRING $name - only $currentTotal total notifications, need $currentThreshold")
                return@Runnable
            }

            debounce.remove(pkg)
            debounceShortDelay.remove(pkg)
            val processedKeys = allNotifications.map { it.sbnKey }.toSet()
            log("info", "[TEST] Processing $currentTotal notification(s) from $name")

            // Dismiss processed notifications (same as real notifications)
            if (spBool("dismiss_on_app_usage", true)) {
                allNotifications.forEach { item ->
                    try {
                        cancelNotification(item.sbnKey)
                        log("info", "[TEST] Dismissed notification: ${item.sbnKey}")
                    } catch (e: Exception) {
                        log("warn", "[TEST] Failed to dismiss ${item.sbnKey}: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
            }

            // Clear processed notifications
            currentGroup.clearProcessedNotifications(processedKeys)
            currentGroup.notifications.removeAll { it.sbnKey in processedKeys }

            executor.execute {
                val previousSummary = currentGroup.summary
                val summary = callAI(pkg, allNotifications, previousSummary)
                if (summary != null) {
                    currentGroup.summary = summary
                    currentGroup.summaryTimestamp = System.currentTimeMillis()
                    val appIcon = getAppIcon(pkg)
                    val notificationColor = currentGroup.notificationColor ?: getNotificationColor(pkg)
                    val notifId = currentGroup.getOrCreateNotificationId("summary")
                    postSummary(pkg, summary, emptyList(), currentTotal, appIcon, notificationColor, notifId!!)
                    log("success", "[TEST] AI summary posted for $name: \"${summary.take(100)}\"")

                    // Cancel original test notifications so only summary remains
                    originalNotificationIds?.forEach { id ->
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            nm.cancel(id)
                            log("info", "[TEST] Cancelled original test notification: id=$id")
                        } catch (e: Exception) {
                            log("warn", "[TEST] Failed to cancel test notification: $e")
                        }
                    }
                } else {
                    log("error", "[TEST] No AI summary for $name — check provider/key/model in Settings")
                }
            }
        }

        debounce[pkg] = runnable
        if (totalCount >= threshold) {
            debounceShortDelay[pkg] = true
            handler.postDelayed(runnable, 800L)
            log("info", "[TEST] Threshold met ($totalCount >= $threshold) — triggering in 800ms")
        } else {
            debounceShortDelay[pkg] = false
            handler.postDelayed(runnable, DEBOUNCE_MS)
            log("info", "[TEST] Below threshold ($totalCount/$threshold) — waiting ${DEBOUNCE_MS}ms for more")
        }
    }

    private fun _handleNotificationInternal(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        if (pkg == applicationContext.packageName) return

        if (!spBool("service_enabled", true)) { log("info", "Service disabled"); return }

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) { log("warn", "No apps selected"); return }
        if (!selected.contains(pkg)) { log("info", "$pkg not selected — skipping"); return }

        log("info", "--- Notification from: $pkg ---")

        val extras = try { sbn.notification.extras } catch (e: Exception) { null }
            ?: run { log("warn", "Cannot access notification extras"); return }
        val title = try {
            extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
        } catch (e: Exception) { null }
            ?: run { log("warn", "No title (${sbn.notification.category})"); return }

        // Extract text: try EXTRA_TEXT, EXTRA_BIG_TEXT, then MessagingStyle messages
        val text: String = run {
            try {
                extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.takeIf { it.length >= 2 }
                    ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.takeIf { it.length >= 2 }
            } catch (_: Exception) { null }
                ?: extractMessagingText(extras)
                ?: run { log("warn", "No usable text"); return }
        }

        // Skip WhatsApp placeholder notifications that contain no real message text
        // (e.g. "2 new messages", "3 new messages" stacking updates)
        if (isWhatsAppPlaceholder(text)) {
            log("info", "Skipping WhatsApp placeholder notification: '$text'")
            return
        }

        // Extract conversation info for grouping
        val conversationId = extractConversationId(extras, title)
        val name = appName(pkg)
        val image = extractImage(sbn.notification)
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        // Get or create the notification group for this package
        val group = buffer.getOrPut(pkg) { NotificationGroup(packageName = pkg) }

        // Check if this is an update to an existing notification (same key in any conversation)
        val existingItem = group.getAllPendingNotifications().find { it.sbnKey == sbn.key }

        // Create item with hash computed from normalized content
        val baseItem = NotificationItem(
            title = title,
            text = text,
            actions = actions,
            sbnKey = sbn.key,
            imageBase64 = image,
            timestamp = System.currentTimeMillis(),
            conversationId = conversationId
        )
        val contentHash = baseItem.computeHash()
        val newItem = baseItem.copy(contentHash = contentHash)

        if (existingItem == null) {
            // Check if notification with this key already exists in ANY conversation (safety check)
            val alreadyExists = group.getAllPendingNotifications().any { it.sbnKey == sbn.key }
            if (alreadyExists) {
                log("warn", "Notification ${sbn.key} already exists in buffer - skipping duplicate")
                return
            }

            // Check for content-based duplicates using hash
            // This catches WhatsApp updates with different keys but same content
            val hashDuplicate = group.getAllPendingNotifications().find { it.contentHash == contentHash }
            if (hashDuplicate != null) {
                log("info", "Duplicate content detected (hash match) - skipping notification with key ${sbn.key}")
                return
            }

            // Add new notification to conversation buffer
            group.addToConversation(newItem)
            group.notifications.add(newItem)
            log("info", "Added new notification to conversation '$conversationId' for $name")
        } else {
            // Update existing notification - but first check if content actually changed using hash
            if (existingItem.contentHash == contentHash) {
                log("info", "Notification update received but content unchanged (hash match) - skipping")
                return
            }

            // Content changed for an existing notification key.
            // Apps like WhatsApp update the same key when stacking new messages.
            // Keep the old notification (it represents a real message) and add the new one.
            group.addToConversation(newItem)
            group.notifications.add(newItem)
            log("info", "Added updated notification to conversation '$conversationId' for $name (content changed, kept old)")
        }

        enforceBufferLimits(pkg)
        log("debug", "Buffer state for $name: conv=${group.conversationBuffers.keys}, total=${group.getAllPendingNotifications().size}, notifList=${group.notifications.size}")

        saveHistory(pkg, name, title, text, image != null)
        recordStat(pkg, intercepted = true, summarised = false)

        // Get notification color if set
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            sbn.notification.color.takeIf { it != 0 }?.let {
                group.notificationColor = it
            }
        }

        val threshold = getThresholdForApp(pkg)
        val convCount = group.getConversationCount(conversationId)
        val totalCount = group.getAllPendingNotifications().size
        log("info", "CAPTURED conv=$convCount/total=$totalCount from $name: title='$title' text='${text.take(80)}' threshold=$threshold conversation=$conversationId")

        // For notification updates: only restart debounce if notification is new.
        // This prevents the same notification from resetting the timer repeatedly.
        // However, if the previous runnable already fired and deferred (removing the
        // debounce), we must schedule a fresh runnable or the buffer will stall.
        if (existingItem == null) {
            // Cancel any pending debounce for this app only for NEW notifications,
            // but NOT if a short-delay (threshold-met) runnable is already waiting.
            // Once threshold is reached we let the timer fire so rapid notifications
            // cannot delay the summary indefinitely.
            val isShortDelayPending = debounceShortDelay[pkg] == true
            if (!isShortDelayPending) {
                debounce[pkg]?.let { handler.removeCallbacks(it) }
                debounce.remove(pkg)
                debounceShortDelay.remove(pkg)
            }
        }

        // Schedule runnable for NEW notifications OR when no debounce is pending.
        // Updates keep the existing runnable only if it is still alive.
        // Once threshold is met and an 800ms runnable is pending, new notifications
        // simply accumulate in the buffer rather than resetting the timer.
        val scheduleRunnable = if (debounce.containsKey(pkg)) {
            existingItem == null && debounceShortDelay[pkg] != true
        } else {
            true
        }
        if (!scheduleRunnable) {
            log("info", "Notification update for $name - keeping existing debounce timer")
        }

        val runnable = object : Runnable {
            override fun run() {
                val currentGroup = buffer[pkg] ?: return
                val threshold = getThresholdForApp(pkg)

                // Get all pending notifications for this app
                val allNotifications = currentGroup.getAllPendingNotifications()
                val totalCount = allNotifications.size

                val bufferDebug = currentGroup.conversationBuffers.map { (k, v) -> "$k=${v.size}" }.joinToString(", ")
                log("info", "RUNNABLE CHECK for $name: total=$totalCount, threshold=$threshold, buffers=[$bufferDebug], notifList=${currentGroup.notifications.size}")
                allNotifications.forEachIndexed { i, it ->
                    log("debug", "  [$i] key=${it.sbnKey} conv=${it.conversationId} hash=${it.contentHash.take(8)}")
                }

                // Simple threshold check - just need enough notifications total
                if (totalCount < threshold) {
                    debounce.remove(pkg)
                    debounceShortDelay.remove(pkg)
                    log("info", "DEFERRING $name - only $totalCount total notifications, need $threshold")
                    return
                }

                // Cooldown check: after a summary is posted for this package, wait
                // before allowing another summary so burst notifications accumulate.
                val cooldownMs = getCooldownForApp(pkg)
                if (cooldownMs > 0) {
                    val lastSummary = lastSummaryTime[pkg] ?: 0L
                    val elapsed = System.currentTimeMillis() - lastSummary
                    if (elapsed < cooldownMs) {
                        val remaining = cooldownMs - elapsed
                        log("info", "Cooldown ACTIVE for $name — ${remaining}ms remaining of ${cooldownMs}ms, deferring summary")
                        debounce[pkg] = this
                        handler.postDelayed(this, remaining)
                        return
                    } else {
                        log("info", "Cooldown EXPIRED for $name — ${elapsed}ms elapsed since last summary (cooldown=${cooldownMs}ms)")
                    }
                } else {
                    log("info", "Cooldown IGNORED for $name — no cooldown configured")
                }

                debounce.remove(pkg)
                debounceShortDelay.remove(pkg)

            // Get all notification keys to process and clear
            val processedKeys = allNotifications.map { it.sbnKey }.toSet()

            // Track keys BEFORE dismissing, so onNotificationRemoved can match them
            // when the system/app later dismisses the originals.
            currentGroup.lastSummarizedKeys.clear()
            currentGroup.lastSummarizedKeys.addAll(processedKeys)
            currentGroup.dismissedSummarizedKeys.clear()

            log("info", "Processing $totalCount notification(s) from $name")

            // Only retain original actions when every buffered notification belongs to the
            // same conversation.  Cross-conversation "Mark as read" / "Reply" actions target
            // a single chat, so attaching them to a multi-conversation summary would only
            // work for one of the bundled chats.
            val retainActions = spBool("retain_original_actions", true)
            val uniqueConversations = allNotifications.map { it.conversationId }.distinct()
            val allActions = if (retainActions && uniqueConversations.size == 1) {
                allNotifications.flatMap { it.actions }.distinctBy { it.title?.toString() }
            } else {
                if (retainActions && uniqueConversations.size > 1) {
                    log("warn", "Skipping action retention — $totalCount notifications span ${uniqueConversations.size} conversations")
                }
                emptyList()
            }

            // Dismiss all processed notifications (skip test keys — they are not real system notifications).
            val activeKeys = if (spBool("dismiss_on_app_usage", true)) {
                val active = mutableSetOf<String>()
                allNotifications.forEach { item ->
                    if (item.sbnKey.startsWith("test_")) {
                        log("info", "Skipping dismiss for test notification: ${item.sbnKey}")
                        return@forEach
                    }
                    try {
                        cancelNotification(item.sbnKey)
                        log("info", "Dismissed notification: ${item.sbnKey}")
                    } catch (e: SecurityException) {
                        log("warn", "Failed to dismiss ${item.sbnKey}: SecurityException — listener may lack cancel permission")
                        active.add(item.sbnKey)
                    } catch (e: Exception) {
                        log("warn", "Failed to dismiss ${item.sbnKey}: ${e.javaClass.simpleName}: ${e.message}")
                        active.add(item.sbnKey)
                    }
                }
                active
            } else emptySet()

            // Clear all processed notifications from buffers
            currentGroup.clearProcessedNotifications(processedKeys)
            currentGroup.notifications.removeAll { it.sbnKey in processedKeys }

            executor.execute {
                // Check if this is an update to previous summary
                val previousSummary = currentGroup.summary
                if (previousSummary != null) {
                    log("info", "Updating previous summary for $name")
                }

                // Send all notifications to AI - let it handle grouping/deduplication
                val summary = callAI(pkg, allNotifications, previousSummary)

                if (summary != null) {
                    if (isNoChangeResponse(summary)) {
                        log("info", "AI indicated no change for $name — skipping notification: \"${summary.take(80)}\"")
                    } else {
                        // Store summary for potential future updates
                        currentGroup.summary = summary
                        currentGroup.summaryTimestamp = System.currentTimeMillis()

                        val appIcon = getAppIcon(pkg)
                        val notificationColor = currentGroup.notificationColor ?: getNotificationColor(pkg)
                        val notifId = currentGroup.getOrCreateNotificationId("summary")
                        postSummary(pkg, summary, allActions, totalCount, appIcon, notificationColor, notifId)
                        recordStat(pkg, intercepted = false, summarised = true)
                        log("success", "AI summary posted for $name: \"${summary.take(100)}\"")
                        val cooldownMs = getCooldownForApp(pkg)
                        if (cooldownMs > 0) {
                            log("info", "Cooldown STARTING for $name — ${cooldownMs}ms cooldown active")
                        }
                        lastSummaryTime[pkg] = System.currentTimeMillis()

                        // Clear dismissal tracking so retryDismiss / dismissRemainingActive
                        // (scheduled 600ms later) don't cancel the summary we just posted.
                        currentGroup.lastSummarizedKeys.clear()
                        currentGroup.dismissedSummarizedKeys.clear()

                        // Immediate sweep for any remaining active notifications from this package.
                        // This closes the race window where apps (e.g. Teams) post new notifications
                        // while the AI call is in flight.
                        dismissRemainingActive(pkg, notifId)

                        // Verify originals were dismissed; retry any that remain.
                        // Also catch notifications whose keys changed (e.g. WhatsApp stacking).
                        handler.postDelayed({
                            retryDismiss(pkg, activeKeys)
                            // Second-pass fallback: dismiss any stragglers that appeared after
                            // the immediate sweep.
                            dismissRemainingActive(pkg, notifId)
                        }, 600)
                    }
                } else {
                    log("error", "No AI summary for $name — enqueuing for retry. Check provider/key/model in Settings")
                    enqueueRetry(pkg, allNotifications)
                }
            }
        }
    }

        // Schedule runnable for NEW notifications or when the previous one expired.
        if (scheduleRunnable) {
            debounce[pkg] = runnable
            if (totalCount >= threshold) {
                // Threshold reached — fire after short delay
                debounceShortDelay[pkg] = true
                handler.postDelayed(runnable, 800L)
                log("info", "Threshold met ($totalCount >= $threshold) — triggering in 800ms")
            } else {
                // Below threshold — wait longer for more notifications
                debounceShortDelay[pkg] = false
                handler.postDelayed(runnable, DEBOUNCE_MS)
                log("info", "Below threshold ($totalCount/$threshold) — waiting ${DEBOUNCE_MS}ms for more")
            }
        }
    }

    /**
     * Detects AI responses that indicate no new content vs actual summaries.
     * Returns true if the response should be skipped (no meaningful update).
     */
    /**
     * Detects WhatsApp (and similar) placeholder text that appears when
     * notifications are stacked, e.g. "2 new messages", "3 new messages".
     * These contain no actual message content and should not be summarized.
     */
    private fun isWhatsAppPlaceholder(text: String): Boolean {
        val trimmed = text.trim()
        // Match patterns like: "2 new messages", "3 new messages", "1 new message"
        return Regex("^\\d+\\s+new\\s+messages?$", RegexOption.IGNORE_CASE).matches(trimmed)
    }

    private fun isNoChangeResponse(text: String): Boolean {
        val lower = text.lowercase()
        // Common patterns AI uses to say "nothing changed" or "no content"
        val noChangePatterns = listOf(
            "no new notifications",
            "no new messages",
            "no new updates",
            "status remains unchanged",
            "remains unchanged",
            "nothing has changed",
            "no change",
            "no updates",
            "still the same",
            "unchanged from",
            "no additional",
            "no further updates",
            "previous summary still applies",
            "same as before",
            "no notification content",
            "no notifications provided",
            "no content provided",
            "no notifications to summarize",
            "nothing to summarize",
            "no new notification content",
            "no new content",
            "cannot summarize",
            "unable to summarize"
        )
        return noChangePatterns.any { pattern -> lower.contains(pattern) }
    }

    private fun extractConversationId(extras: android.os.Bundle, title: String): String? {
        return try {
            // Try to get conversation title/sender from messaging style
            val rawId = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
                ?: extras.getCharSequence("android.messagingStyleUser.displayName")?.toString()
                ?: title.takeIf { it.contains(":") }?.substringBefore(":")?.trim()
                ?: title

            // Normalize: strip patterns like "(2 messages)", "(3 new messages)" that WhatsApp adds
            normalizeConversationId(rawId)
        } catch (_: Exception) { null }
    }

    /**
     * Normalizes conversation ID by stripping app-added metadata like message counts.
     * "General Chat (2 messages)" → "General Chat"
     * "General Chat (3 new messages)" → "General Chat"
     */
    private fun normalizeConversationId(id: String?): String? {
        if (id == null) return null

        // Strip "(N messages)" or "(N new messages)" patterns
        return id.replace(Regex("\\s*\\(\\d+\\s+(new\\s+)?messages?\\)$"), "").trim()
            .takeIf { it.isNotEmpty() }
    }

    /**
     * Retry dismissing notifications that failed the first cancelNotification attempt.
     * Some OEM skins restrict cancelNotification; this gives it another shot after
     * the summary has been posted, and logs exactly which keys are stuck.
     */
    private fun retryDismiss(pkg: String, keys: Set<String>) {
        try {
            val active = getActiveNotifications()?.filter { it.packageName == pkg && it.key in keys } ?: emptyList()
            if (active.isEmpty()) return
            log("warn", "Retrying dismiss for ${active.size} stuck notification(s) from $pkg")
            active.forEach { sbn ->
                try {
                    cancelNotification(sbn.key)
                    log("info", "Retry dismiss succeeded: ${sbn.key}")
                } catch (e: Exception) {
                    log("error", "Retry dismiss FAILED for ${sbn.key}: ${e.javaClass.simpleName}: ${e.message}")
                }
            }
        } catch (e: Exception) {
            log("error", "retryDismiss crash: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    /**
     * Dismisses any remaining active notifications from the target package
     * after a summary has been posted. This catches notifications whose keys
     * changed between capture and dismiss (e.g. WhatsApp stacking updates).
     * Skips our own summary notification and any keys in [skipKeys].
     */
    private fun dismissRemainingActive(pkg: String, summaryNotifId: Int, skipKeys: Set<String> = emptySet()) {
        try {
            val active = getActiveNotifications()?.filter {
                it.packageName == pkg && it.id != summaryNotifId && it.key !in skipKeys
            } ?: emptyList()
            if (active.isEmpty()) return
            log("info", "dismissRemainingActive: found ${active.size} remaining notification(s) from $pkg")
            active.forEach { sbn ->
                try {
                    cancelNotification(sbn.key)
                    log("info", "dismissRemainingActive: cancelled ${sbn.key}")
                } catch (e: Exception) {
                    log("warn", "dismissRemainingActive: failed to cancel ${sbn.key}: ${e.javaClass.simpleName}")
                }
            }
        } catch (e: Exception) {
            log("error", "dismissRemainingActive crash: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun getNotificationColor(pkg: String): Int? {
        return try {
            val colorStr = spStr("notification_color_$pkg", "")
            if (colorStr.isNotEmpty()) {
                Color.parseColor(colorStr)
            } else null
        } catch (_: Exception) { null }
    }

    private fun getAppIcon(pkg: String): Bitmap? {
        return try {
            val appInfo = packageManager.getApplicationInfo(pkg, 0)
            val drawable = packageManager.getApplicationIcon(appInfo)
            drawableToBitmap(drawable)
        } catch (_: Exception) { null }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        val bitmap = Bitmap.createBitmap(
            drawable.intrinsicWidth.coerceAtLeast(1),
            drawable.intrinsicHeight.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888
        )
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    // ── AI dispatch ────────────────────────────────────────────────────────────

    private fun callAI(pkg: String, buf: List<NotificationItem>, previousSummary: String? = null, isDigest: Boolean = false): String? {
        // Defensive copy and validate
        val notifications = buf.toList()
        if (notifications.isEmpty()) {
            log("error", "AI call with EMPTY notification list - this is a bug!")
            return null
        }

        // Build ordered provider list with deduplication
        val providers = mutableListOf<String>()

        // WiFi-based provider switching: if connected to a known SSID, use its provider first
        val currentSsid = getCurrentWifiSsid()
        if (currentSsid != null) {
            val wifiSsid1 = spStr("wifi_ssid_1", "")
            val wifiProvider1 = spStr("wifi_provider_1", "")
            val wifiSsid2 = spStr("wifi_ssid_2", "")
            val wifiProvider2 = spStr("wifi_provider_2", "")
            when {
                wifiSsid1.isNotEmpty() && wifiProvider1.isNotEmpty() && currentSsid == wifiSsid1 -> {
                    log("info", "WiFi match: using provider '$wifiProvider1' for SSID '$currentSsid'")
                    providers.add(wifiProvider1)
                }
                wifiSsid2.isNotEmpty() && wifiProvider2.isNotEmpty() && currentSsid == wifiSsid2 -> {
                    log("info", "WiFi match: using provider '$wifiProvider2' for SSID '$currentSsid'")
                    providers.add(wifiProvider2)
                }
            }
        }

        val primary = spStr("ai_provider", "ollama")
        if (primary.isNotEmpty() && !providers.contains(primary)) providers.add(primary)
        val backup1 = spStr("backup_provider_1", "")
        if (backup1.isNotEmpty() && !providers.contains(backup1)) providers.add(backup1)
        val backup2 = spStr("backup_provider_2", "")
        if (backup2.isNotEmpty() && !providers.contains(backup2)) providers.add(backup2)

        if (providers.isEmpty()) {
            log("error", "AI SKIP: no providers configured")
            return null
        }

        val length  = spInt("summary_length", 2)

        // Build length instruction
        val lengthInstruction = when (length) {
            1 -> "Keep the summary very brief - one short sentence maximum. Be extremely concise."
            3 -> "Provide a detailed summary with 2-3 sentences covering key information. Include important details."
            else -> "Provide a clear, concise summary in one sentence. Balance brevity with informativeness."
        }

        val hint = when (length) {
            1 -> "in one very brief sentence"
            3 -> "in 2-3 sentences with key details"
            else -> "in one clear sentence"
        }

        val name = appName(pkg)

        // Deduplicate notifications by content (same title+text = same message)
        // This prevents WhatsApp from sending duplicate content with different keys
        val uniqueNotifications = notifications.distinctBy { "${it.title}:${it.text}" }
        val dupesRemoved = notifications.size - uniqueNotifications.size
        if (dupesRemoved > 0) {
            log("info", "Removed $dupesRemoved duplicate notification(s) by content")
        }

        // Filter out notifications with effectively empty or sender-only text.
        // WhatsApp sometimes produces text like "~ Paul Smith: " with no actual message body.
        val meaningfulNotifications = uniqueNotifications.filter { item ->
            val trimmed = item.text.trim()
            if (trimmed.isEmpty()) {
                log("info", "Filtered notification with empty text from ${item.title}")
                return@filter false
            }
            if (trimmed.length < 2) {
                log("info", "Filtered notification with near-empty text: '${trimmed}'")
                return@filter false
            }
            // Skip text that appears to be just a sender name prefix with no message after colon
            if (trimmed.matches(Regex("~?\\s*[^:]{1,30}:\\s*$"))) {
                log("info", "Filtered sender-only text: '${trimmed.take(40)}'")
                return@filter false
            }
            true
        }

        if (meaningfulNotifications.isEmpty()) {
            log("warn", "All ${uniqueNotifications.size} notification(s) had empty/meaningless text — skipping AI call")
            return null
        }
        if (meaningfulNotifications.size < uniqueNotifications.size) {
            log("info", "Filtered ${uniqueNotifications.size - meaningfulNotifications.size} empty/meaningless notification(s), ${meaningfulNotifications.size} remain")
        }

        // Group notifications by sender/conversation for better AI understanding
        val groupedBySender = meaningfulNotifications.groupBy { it.conversationId ?: it.title }
        val msgs = if (groupedBySender.size > 1) {
            // Multiple senders - group them with headers
            groupedBySender.entries.joinToString("\n\n") { (sender, notifs) ->
                // Also dedupe within each sender group
                val uniqueTexts = notifs.distinctBy { it.text }
                val messageLines = uniqueTexts.joinToString("\n") { "• ${it.text}" }
                "**$sender:**\n$messageLines"
            }
        } else {
            // Single sender - simple bullet list, deduped
            val uniqueTexts = meaningfulNotifications.distinctBy { it.text }
            uniqueTexts.joinToString("\n") { "• ${it.title}: ${it.text}" }
        }

        val customPrompt = if (isDigest) spStr("digest_prompt", "") else spStr("custom_prompt", "")

        // Debug: log what we're sending
        log("info", "Building prompt for $name with ${meaningfulNotifications.size} meaningful notifications (was ${notifications.size}) from ${groupedBySender.size} sender(s)")
        log("info", "Notifications content: ${msgs.take(200)}")
        log("info", "msgs variable length: ${msgs.length} chars")

        // Build prompt - keep it simple and direct
        // Custom prompt variables available:
        //   {app_name}          - Display name of the app (e.g., "WhatsApp")
        //   {notifications}     - Formatted list of notifications as bullet points
        //   {count}             - Number of notifications being summarized
        //   {length}            - Summary length setting (1=brief, 2=balanced, 3=detailed)
        //   {length_instruction} - Full length instruction text for the AI
        //   {hint}              - Concise hint for the AI (e.g., "in one very brief sentence")
        // Determine if we have multiple senders to adjust the prompt
        val senderContext = if (groupedBySender.size > 1) {
            " Notifications are grouped by sender below."
        } else ""

        // Build AI prompt with clear instructions about grouping and deduplication
        val instructions = """- Group notifications by conversation/thread when present
- If the same message appears multiple times, mention it only once
- Focus on unique content and different senders
- Ignore metadata like "(2 messages)" or "2 new messages" prefixes
- Summarize naturally as a coherent update"""

        val prompt = if (customPrompt.isNotEmpty()) {
            // User-defined custom prompt - substitute variables (including {instructions})
            customPrompt
                .replace("{app_name}", name)
                .replace("{notifications}", msgs)
                .replace("{count}", notifications.size.toString())
                .replace("{length}", length.toString())
                .replace("{length_instruction}", lengthInstruction)
                .replace("{hint}", hint)
                .replace("{instructions}", instructions)
        } else {
            // Default prompt with clear grouping/deduplication instructions
            if (isDigest) {
                """You are generating a periodic digest summary of notifications accumulated over time.

Context: These notifications may span multiple apps and conversations. Group related items, prioritise urgent or actionable messages, and provide a coherent overview.

App: $name
Notifications:
$msgs
Total count: ${notifications.size}

Provide a well-structured digest. Highlight time-sensitive items and anything requiring action. Use clear sections if multiple topics are involved. $hint."""
            } else if (previousSummary != null) {
                """You are summarizing notifications from $name.

Instructions:
$instructions

Previous summary: $previousSummary

New notifications to incorporate:
$msgs

Provide an updated $hint that covers BOTH the previous summary AND the new notifications above. Merge them into a single coherent summary. Do not discard or ignore the previous summary content. Be direct and concise."""
            } else {
                """Summarize these $name notifications $hint:

Instructions:
$instructions

Notifications:
$msgs

Provide a clear, concise summary."""
            }
        }

        log("info", "Final prompt length: ${prompt.length} chars")
        log("info", "Full prompt: $prompt")
        val images = notifications.mapNotNull { it.imageBase64 }

        for ((index, provider) in providers.withIndex()) {
            val tier = when (index) {
                0 -> "primary"
                1 -> "secondary"
                else -> "tertiary"
            }
            val apiKey  = spStr("api_key_$provider", "")
            val model   = spStr("model_$provider", "")
            val baseUrl = spStr("base_url_$provider", "")

            log("info", "AI call [$tier]: provider=$provider model=${model.ifEmpty { "(none)" }} url=${baseUrl.ifEmpty { "(default)" }} hasKey=${apiKey.isNotEmpty()}")

            if (model.isEmpty() && provider != "gemini_nano") {
                log("warn", "AI SKIP [$tier]: no model set for $provider")
                continue
            }
            if (provider == "ollama" && baseUrl.isEmpty()) {
                log("warn", "AI SKIP [$tier]: no URL set for Ollama")
                continue
            }
            if (provider == "gemini" && apiKey.isEmpty()) {
                log("warn", "AI SKIP [$tier]: no API key set for Gemini")
                continue
            }

            val result = try {
                when (provider) {
                    "ollama"      -> callOllama(baseUrl, model, prompt, apiKey)
                    "gemini"      -> callGemini(apiKey, model, prompt, images)
                    "gemini_nano" -> callGeminiNano(prompt)
                    "claude"      -> {
                        val url = baseUrl.ifEmpty { "https://api.anthropic.com" }
                        callClaude(url, apiKey, model, prompt)
                    }
                    "openai"      -> {
                        val url = baseUrl.ifEmpty { "https://api.openai.com" }
                        callOpenAI(url, apiKey, model, prompt)
                    }
                    "openrouter"  -> {
                        val url = baseUrl.ifEmpty { "https://openrouter.ai" }
                        callOpenAI(url, apiKey, model, prompt)
                    }
                    "local"       -> callOpenAI(baseUrl, apiKey, model, prompt)
                    else -> { log("warn", "Unknown provider: $provider"); null }
                }
            } catch (e: Exception) {
                log("error", "AI exception [$tier/$provider]: ${e.javaClass.simpleName}: ${e.message}")
                null
            }

            if (result != null) {
                log("success", "AI response OK from $tier provider $provider — ${result.length} chars")
                return result
            } else {
                log("warn", "AI call failed for $tier provider $provider — trying next")
            }
        }

        log("error", "All AI providers failed for $pkg")
        return null
    }

    // ── Ollama ─────────────────────────────────────────────────────────────────
    // POST {baseUrl}/api/generate
    // { "model": "...", "prompt": "...", "stream": false }
    // Response: { "response": "..." }

    private fun callOllama(baseUrl: String, model: String, prompt: String, apiKey: String): String? {
        val base = baseUrl.trimEnd('/')

        // Detect OpenAI-compatible endpoint (contains /v1)
        return if (base.contains("/v1")) {
            callOllamaOpenAICompatible(base, model, prompt, apiKey)
        } else {
            callOllamaNative(base, model, prompt, apiKey)
        }
    }

    private fun callOllamaNative(baseUrl: String, model: String, prompt: String, apiKey: String): String? {
        val endpoint = "$baseUrl/api/generate"
        log("info", "Ollama Native POST $endpoint model=$model")

        val body = JSONObject().apply {
            put("model", model)
            put("prompt", prompt)
            put("stream", false)
        }.toString()

        val conn = openConn(URL(endpoint), emptyMap<String, String>().let {
            val h = mutableMapOf("Content-Type" to "application/json")
            if (apiKey.isNotEmpty()) h["Authorization"] = "Bearer $apiKey"
            h
        }, readTimeout = 120000)

        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        if (code == 200) {
            val responseText = conn.inputStream.reader().readText()
            val json = JSONObject(responseText)
            val result = json.getString("response").trim()
            log("success", "Ollama Native response OK — ${result.length} chars")
            return result
        }
        val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
        log("error", "Ollama Native HTTP $code: $errBody")
        return null
    }

    private fun callOllamaOpenAICompatible(baseUrl: String, model: String, prompt: String, apiKey: String): String? {
        val endpoint = "$baseUrl/chat/completions"
        log("info", "Ollama OpenAI-compat POST $endpoint model=$model")

        val body = JSONObject().apply {
            put("model", model)
            put("stream", false)
            put("messages", JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "system")
                    put("content", "You are a notification summarizer. Your task is to summarize the notifications provided by the user. Always provide a summary - never say there are no notifications or nothing to summarize. Be concise and direct.")
                })
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", prompt)
                })
            })
        }.toString()

        val headers = mutableMapOf("Content-Type" to "application/json")
        if (apiKey.isNotEmpty()) headers["Authorization"] = "Bearer $apiKey"

        log("info", "Ollama OpenAI-compat prompt: ${prompt.take(300)}...")

        return try {
            val conn = openConn(URL(endpoint), headers, readTimeout = 60000)
            conn.outputStream.writer().use { it.write(body) }
            conn.outputStream.flush()
            conn.outputStream.close()
            val code = conn.responseCode
            log("info", "Ollama OpenAI-compat response code: $code")
            if (code == 200) {
                val responseText = conn.inputStream.reader().readText()
                log("info", "Ollama raw response: ${responseText.take(500)}")
                val json = JSONObject(responseText)
                val result = json.getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("message")
                    .getString("content").trim()
                log("success", "Ollama OpenAI-compat response OK — ${result.length} chars: ${result.take(100)}")
                return result
            }
            val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
            log("error", "Ollama OpenAI-compat HTTP $code: $errBody")
            null
        } catch (e: Exception) {
            log("error", "Ollama OpenAI-compat exception: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    // ── Gemini ─────────────────────────────────────────────────────────────────
    // POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
    // Body: { "contents": [{ "parts": [{ "text": "..." }] }], "generationConfig": { "maxOutputTokens": 150 } }
    // Response: { "candidates": [{ "content": { "parts": [{ "text": "..." }] } }] }

    private fun callGemini(apiKey: String, model: String, prompt: String, images: List<String>): String? {
        val endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey"
        log("info", "Gemini POST model=$model images=${images.size}")

        val parts = JSONArray()
        // Add images first if present
        images.forEach { b64 ->
            parts.put(JSONObject().apply {
                put("inline_data", JSONObject().apply {
                    put("mime_type", "image/jpeg")
                    put("data", b64)
                })
            })
        }
        parts.put(JSONObject().apply { put("text", prompt) })

        val body = JSONObject().apply {
            put("contents", JSONArray().put(JSONObject().apply {
                put("parts", parts)
            }))
            put("generationConfig", JSONObject().apply {
                put("maxOutputTokens", 150)
                put("temperature", 0.3)
            })
        }.toString()

        val conn = openConn(URL(endpoint), mapOf("Content-Type" to "application/json"))
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        if (code == 200) {
            val json = JSONObject(conn.inputStream.reader().readText())
            val result = json.getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text").trim()
            log("success", "Gemini response OK — ${result.length} chars")
            return result
        }
        val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
        log("error", "Gemini HTTP $code: $errBody")
        return null
    }

    // ── Gemini Nano ────────────────────────────────────────────────────────────
    // On-device inference via AICore — requires Pixel 8+ or supported device
    // Falls back gracefully if not available

    private fun callGeminiNano(prompt: String): String? {
        return try {
            kotlinx.coroutines.runBlocking {
                val generation = com.google.mlkit.genai.prompt.Generation.getClient()
                val status = generation.checkStatus()
                when (status) {
                    com.google.mlkit.genai.common.FeatureStatus.AVAILABLE -> {
                        val request = com.google.mlkit.genai.prompt.generateContentRequest(
                            com.google.mlkit.genai.prompt.TextPart(prompt)
                        ) {
                            maxOutputTokens = 150
                        }
                        val response = generation.generateContent(request)
                        val text = response.candidates[0].text?.trim()
                        if (text != null) {
                            log("success", "Gemini Nano response OK — ${text.length} chars")
                        } else {
                            log("warn", "Gemini Nano returned empty response")
                        }
                        text
                    }
                    com.google.mlkit.genai.common.FeatureStatus.DOWNLOADABLE -> {
                        log("info", "Gemini Nano model downloadable — starting download")
                        generation.download().collect { }
                        log("info", "Gemini Nano download complete — retrying inference")
                        val request = com.google.mlkit.genai.prompt.generateContentRequest(
                            com.google.mlkit.genai.prompt.TextPart(prompt)
                        ) {
                            maxOutputTokens = 150
                        }
                        val response = generation.generateContent(request)
                        response.candidates[0].text?.trim()
                    }
                    com.google.mlkit.genai.common.FeatureStatus.DOWNLOADING -> {
                        log("warn", "Gemini Nano model is downloading — skipping")
                        null
                    }
                    else -> {
                        log("warn", "Gemini Nano unavailable on this device: status=$status")
                        null
                    }
                }
            }
        } catch (e: Exception) {
            log("error", "Gemini Nano exception: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    // ── Claude (Anthropic) ─────────────────────────────────────────────────────
    // POST {baseUrl}/v1/messages
    // Headers: x-api-key, anthropic-version: 2023-06-01
    // Body: { "model": "...", "max_tokens": 150, "messages": [{"role":"user","content":"..."}] }
    // Response: { "content": [{"type":"text","text":"..."}] }

    private fun callClaude(baseUrl: String, apiKey: String, model: String, prompt: String): String? {
        val endpoint = "${baseUrl.trimEnd('/')}/v1/messages"
        log("info", "Claude POST $endpoint model=$model")

        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 150)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", prompt)
            }))
        }.toString()

        val conn = openConn(URL(endpoint), mapOf(
            "Content-Type" to "application/json",
            "x-api-key" to apiKey,
            "anthropic-version" to "2023-06-01"
        ))
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        if (code == 200) {
            val json = JSONObject(conn.inputStream.reader().readText())
            val result = json.getJSONArray("content")
                .getJSONObject(0)
                .getString("text").trim()
            log("success", "Claude response OK — ${result.length} chars")
            return result
        }
        val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
        log("error", "Claude HTTP $code: $errBody")
        return null
    }

    // ── OpenAI-compatible (OpenAI / OpenRouter / Local) ────────────────────────
    // POST {baseUrl}/v1/chat/completions
    // Headers: Authorization: Bearer {apiKey}
    // Body: { "model": "...", "max_tokens": 150, "messages": [{"role":"user","content":"..."}] }
    // Response: { "choices": [{"message":{"content":"..."}}] }

    private fun callOpenAI(baseUrl: String, apiKey: String, model: String, prompt: String): String? {
        val base = baseUrl.trimEnd('/')
        val endpoint = if (base.endsWith("/v1")) "$base/chat/completions" else "$base/v1/chat/completions"
        log("info", "OpenAI-compat POST $endpoint model=$model")

        val body = JSONObject().apply {
            put("model", model)
            put("stream", false)
            put("messages", JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "system")
                    put("content", "Provide a concise bullet summary. Reply with ONLY the bullet points, no other text or JSON.")
                })
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", prompt)
                })
            })
        }.toString()

        val headers = mutableMapOf("Content-Type" to "application/json")
        if (apiKey.isNotEmpty()) headers["Authorization"] = "Bearer $apiKey"

        val conn = openConn(URL(endpoint), headers, readTimeout = 60000)
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        if (code == 200) {
            val json = JSONObject(conn.inputStream.reader().readText())
            val result = json.getJSONArray("choices")
                .getJSONObject(0)
                .getJSONObject("message")
                .getString("content").trim()
            log("success", "OpenAI-compat response OK — ${result.length} chars")
            return result
        }
        val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
        log("error", "OpenAI-compat HTTP $code: $errBody")
        return null
    }

    // ── Post summary notification ──────────────────────────────────────────────

    private fun postSummary(pkg: String, summary: String,
                            actions: List<Notification.Action>, count: Int,
                            appIcon: Bitmap? = null, notificationColor: Int? = null,
                            notificationId: Int? = null) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val groupId = "notify_ai_group_$pkg"
        val channelId = "notify_ai_v2_$pkg"   // v2 = HIGH importance; v1 channels were DEFAULT
        val name = appName(pkg)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannelGroup(NotificationChannelGroup(groupId, name))
            val ch = NotificationChannel(channelId, "$name Summaries",
                NotificationManager.IMPORTANCE_HIGH).apply {
                group = groupId
                enableVibration(true)
                setShowBadge(true)
            }
            nm.createNotificationChannel(ch)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId)
        else @Suppress("DEPRECATION") Notification.Builder(this)

        val label = if (count > 1) "$count messages · " else ""
        builder
            .setContentTitle("$name · AI Summary")
            .setContentText(summary)
            .setStyle(Notification.BigTextStyle().bigText(summary)
                .setSummaryText("${label}AI summary"))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setGroup(groupId)

        // Add click intent to open the originating app
        val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pendingIntent = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setContentIntent(pendingIntent)
            log("info", "Added launch intent for $name")
        } else {
            log("warn", "No launch intent found for $name")
        }

        // Set app icon as large icon if available
        if (appIcon != null) {
            builder.setLargeIcon(appIcon)
            log("info", "Set app icon for $name notification")
        }

        // Set custom notification color if available
        notificationColor?.let {
            builder.setColor(it)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setColorized(true)
            }
            log("info", "Set notification color for $name: #${Integer.toHexString(it)}")
        }

        // Compute notification ID early so action wrappers can reference it
        val finalNotificationId = notificationId ?: "${pkg}:summary:${System.currentTimeMillis()}".hashCode()

        // Retain original notification actions (Reply, Mark as read, etc.)
        // We wrap each action so tapping it first cancels our summary notification,
        // then forwards the original intent. Without this the summary lingers
        // after the user taps "Mark as read" because the original app's PendingIntent
        // only knows how to dismiss its own notification.
        val retainActions = spBool("retain_original_actions", true)
        log("info", "Actions settings: retain_original_actions=$retainActions, found=${actions.size}")
        if (retainActions && actions.isNotEmpty()) {
            log("info", "Attaching ${actions.size} original action(s) to summary")
            actions.take(5).forEachIndexed { index, action ->
                try {
                    val actionIntent = action.actionIntent
                    if (actionIntent != null) {
                        val actionKey = "${pkg}_${finalNotificationId}_${index}_${System.currentTimeMillis()}"
                        actionMap[actionKey] = actionIntent
                        val wrapIntent = Intent(this, SummaryActionReceiver::class.java).apply {
                            putExtra("pkg", pkg)
                            putExtra("notifId", finalNotificationId)
                            putExtra("actionKey", actionKey)
                        }
                        val wrapPi = PendingIntent.getBroadcast(
                            this, actionKey.hashCode(), wrapIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val wrappedAction = Notification.Action.Builder(
                            android.R.drawable.ic_menu_send,
                            action.title,
                            wrapPi
                        ).build()
                        builder.addAction(wrappedAction)
                        log("info", "  + wrapped action: ${action.title}")
                    } else {
                        builder.addAction(action)
                        log("info", "  + action (no intent): ${action.title}")
                    }
                } catch (e: Exception) {
                    log("warn", "  Could not attach action '${action.title}': ${e.javaClass.simpleName}: ${e.message}")
                }
            }
        } else {
            log("info", "No actions attached: retainActions=$retainActions, actionsEmpty=${actions.isEmpty()}")
        }

        nm.notify(finalNotificationId, builder.build())
        log("success", "Summary notification posted for $name (id=$finalNotificationId)")
    }

    private fun postStatusNotification(title: String, text: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "notify_ai_status"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(NotificationChannel(channelId,
                    "Notify AI Status", NotificationManager.IMPORTANCE_LOW))
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, channelId)
            else @Suppress("DEPRECATION") Notification.Builder(this)
            builder.setContentTitle(title).setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)   // persistent — prevents Android killing the service
                .setAutoCancel(false)
            nm.notify("status".hashCode(), builder.build())
        } catch (e: Exception) { log("warn", "Status notification failed: ${e.message}") }
    }

    // ── MessagingStyle text extraction ────────────────────────────────────────

    private fun extractMessagingText(extras: android.os.Bundle): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        return try {
            @Suppress("DEPRECATION")
            val msgs = try { extras.getParcelableArray(Notification.EXTRA_MESSAGES) } catch (_: ClassCastException) { null } ?: return null
            val texts = msgs.mapNotNull { m ->
                try {
                    (m as? android.os.Bundle)?.getCharSequence("text")?.toString()
                        ?.takeIf { it.length >= 3 }
                } catch (_: Exception) { null }
            }
            if (texts.isEmpty()) null else texts.takeLast(5).joinToString(" | ")
        } catch (_: Exception) { null }
    }

    // ── Image extraction ───────────────────────────────────────────────────────

    private fun extractImage(n: Notification): String? {
        return try {
            val extras = n.extras
            val pic = extras.getParcelable<Bitmap>(Notification.EXTRA_PICTURE)
            if (pic != null) return toBase64(pic)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val icon = extras.getParcelable<Icon>(Notification.EXTRA_LARGE_ICON)
                if (icon != null) {
                    val d = icon.loadDrawable(this)
                    if (d is BitmapDrawable) return toBase64(d.bitmap)
                }
            }
            null
        } catch (_: Exception) { null }
    }

    private fun toBase64(bmp: Bitmap): String? {
        return try {
            val max = 512
            val scaled = if (bmp.width > max || bmp.height > max) {
                val r = bmp.width.toFloat() / bmp.height
                val (w, h) = if (bmp.width > bmp.height) Pair(max, (max / r).toInt())
                else Pair((max * r).toInt(), max)
                Bitmap.createScaledBitmap(bmp, w, h, true)
            } else bmp
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) { null }
    }

    // ── HTTP helper ────────────────────────────────────────────────────────────

    private fun openConn(url: URL, headers: Map<String, String>,
                         readTimeout: Int = 30000): HttpURLConnection {
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            if (!headers.containsKey("Content-Type"))
                setRequestProperty("Content-Type", "application/json")
            // Some APIs require a User-Agent header
            if (!headers.containsKey("User-Agent"))
                setRequestProperty("User-Agent", "NotifyAI/1.0")
            connectTimeout = 15000
            this.readTimeout = readTimeout
            doOutput = true
            // Disable caching and connection reuse which can cause issues
            useCaches = false
            defaultUseCaches = false
        }
    }

    // ── Logging ────────────────────────────────────────────────────────────────

    private fun log(level: String, msg: String) {
        Log.d(TAG, "[$level] $msg")
        try {
            val sp = sp()
            val key = "flutter.service_log"
            val arr = try { JSONArray(sp.getString(key, "[]")) } catch (_: Exception) { JSONArray() }
            val ts = SimpleDateFormat("HH:mm:ss dd/MM", Locale.getDefault()).format(Date())
            arr.put(JSONObject().apply { put("timestamp", ts); put("level", level); put("message", msg) })
            val trim = JSONArray()
            val start = maxOf(0, arr.length() - 500)
            for (i in start until arr.length()) trim.put(arr[i])
            sp.edit().putString(key, trim.toString()).apply()
        } catch (_: Exception) {}
    }

    // ── History ────────────────────────────────────────────────────────────────

    private fun saveHistory(pkg: String, name: String, title: String,
                            msg: String, hadImage: Boolean) {
        try {
            val sp = sp()
            val key = "flutter.notification_history"
            val arr = try { JSONArray(sp.getString(key, "[]")) } catch (_: Exception) { JSONArray() }
            val ts = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            arr.put(JSONObject().apply {
                put("packageName", pkg); put("appName", name)
                put("title", title); put("message", msg)
                put("timestamp", ts); put("hadImage", hadImage)
            })
            val cutoff = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                .format(Date(System.currentTimeMillis() - 30L * 86400000))
            val pruned = JSONArray()
            for (i in 0 until arr.length()) {
                try {
                    val o = arr.getJSONObject(i)
                    if (o.getString("timestamp").substring(0, 10) >= cutoff) pruned.put(o)
                } catch (_: Exception) {}
            }
            sp.edit().putString(key, pruned.toString()).apply()
        } catch (e: Exception) { log("warn", "saveHistory failed: ${e.message}") }
    }

    // ── Stats ──────────────────────────────────────────────────────────────────

    private fun recordStat(pkg: String, intercepted: Boolean, summarised: Boolean) {
        try {
            val sp = sp()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val key = "flutter.stats_${pkg}_$today"
            val obj = try { JSONObject(sp.getString(key, "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            if (intercepted) obj.put("intercepted", obj.optInt("intercepted") + 1)
            if (summarised) obj.put("summarised", obj.optInt("summarised") + 1)
            sp.edit().putString(key, obj.toString()).apply()
            val allKey = "flutter.stats_all_keys"
            val all = try { JSONArray(sp.getString(allKey, "[]")) } catch (_: Exception) { JSONArray() }
            var found = false
            for (i in 0 until all.length()) if (all.getString(i) == key) { found = true; break }
            if (!found) { all.put(key); sp.edit().putString(allKey, all.toString()).apply() }
            
            // Also write to file for persistence
            try {
                val statsDir = File(filesDir, "stats")
                statsDir.mkdirs()
                val statsFile = File(statsDir, "$today.json")
                val stats = try {
                    if (statsFile.exists()) JSONObject(statsFile.readText()) else JSONObject()
                } catch (_: Exception) { JSONObject() }
                val pkgStats = stats.optJSONObject(pkg) ?: JSONObject()
                if (intercepted) pkgStats.put("intercepted", pkgStats.optInt("intercepted") + 1)
                if (summarised) pkgStats.put("summarised", pkgStats.optInt("summarised") + 1)
                stats.put(pkg, pkgStats)
                statsFile.writeText(stats.toString(2))
            } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    // ── Digest Alarms ──────────────────────────────────────────────────────────

    fun scheduleDigestAlarms() {
        try {
            cancelDigestAlarms()
            if (!spBool("digest_enabled", false)) return
            val alarmMgr = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val scheduleType = spStr("digest_schedule_type", "fixed_times")
            val now = System.currentTimeMillis()
            when (scheduleType) {
                "fixed_times" -> {
                    val times = spList("digest_times")
                    if (times.isEmpty()) return
                    times.forEach { timeStr ->
                        scheduleExactAlarm(alarmMgr, timeStr, "digest_fixed_${timeStr.hashCode()}")
                    }
                    log("info", "Scheduled ${times.size} fixed-time digest alarm(s)")
                }
                "interval" -> {
                    val intervalMin = spInt("digest_interval_minutes", 120)
                    val intervalMs = intervalMin * 60_000L
                    val intent = Intent(this, DigestReceiver::class.java).apply {
                        action = DigestReceiver.ACTION_DIGEST
                    }
                    val pending = PendingIntent.getBroadcast(
                        this, "digest_interval".hashCode(), intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmMgr.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, now + intervalMs, pending)
                    } else {
                        alarmMgr.setExact(android.app.AlarmManager.RTC_WAKEUP, now + intervalMs, pending)
                    }
                    log("info", "Scheduled interval digest alarm in ${intervalMin} min")
                }
                "daily" -> {
                    val timeStr = spStr("digest_daily_time", "09:00")
                    scheduleExactAlarm(alarmMgr, timeStr, "digest_daily", repeatDaily = true)
                    log("info", "Scheduled daily digest alarm at $timeStr")
                }
                "weekly" -> {
                    val day = spInt("digest_weekly_day", 1)
                    val timeStr = spStr("digest_weekly_time", "09:00")
                    scheduleWeeklyAlarm(alarmMgr, day, timeStr)
                    log("info", "Scheduled weekly digest alarm on day $day at $timeStr")
                }
            }
        } catch (e: Exception) {
            log("error", "scheduleDigestAlarms failed: ${e.message}")
        }
    }

    private fun scheduleExactAlarm(alarmMgr: android.app.AlarmManager, timeStr: String, requestCode: String, repeatDaily: Boolean = false) {
        val parts = timeStr.split(":")
        if (parts.size != 2) return
        val hour = parts[0].toIntOrNull() ?: return
        val minute = parts[1].toIntOrNull() ?: return
        val cal = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(java.util.Calendar.DAY_OF_YEAR, if (repeatDaily) 1 else 1)
        }
        val intent = Intent(this, DigestReceiver::class.java).apply {
            action = DigestReceiver.ACTION_DIGEST
        }
        val pending = PendingIntent.getBroadcast(
            this, requestCode.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmMgr.canScheduleExactAlarms()) {
                alarmMgr.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
            } else {
                alarmMgr.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
            }
        } else {
            alarmMgr.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
        }
    }

    private fun scheduleWeeklyAlarm(alarmMgr: android.app.AlarmManager, day: Int, timeStr: String) {
        val parts = timeStr.split(":")
        if (parts.size != 2) return
        val hour = parts[0].toIntOrNull() ?: return
        val minute = parts[1].toIntOrNull() ?: return
        val cal = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.DAY_OF_WEEK, when(day) { 0 -> java.util.Calendar.SUNDAY; 1 -> java.util.Calendar.MONDAY; 2 -> java.util.Calendar.TUESDAY; 3 -> java.util.Calendar.WEDNESDAY; 4 -> java.util.Calendar.THURSDAY; 5 -> java.util.Calendar.FRIDAY; else -> java.util.Calendar.SATURDAY })
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(java.util.Calendar.WEEK_OF_YEAR, 1)
        }
        val intent = Intent(this, DigestReceiver::class.java).apply {
            action = DigestReceiver.ACTION_DIGEST
        }
        val pending = PendingIntent.getBroadcast(
            this, "digest_weekly_${day}_${hour}_${minute}".hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmMgr.canScheduleExactAlarms()) {
                alarmMgr.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
            } else {
                alarmMgr.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
            }
        } else {
            alarmMgr.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, cal.timeInMillis, pending)
        }
    }

    fun cancelDigestAlarms() {
        try {
            val alarmMgr = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val requestCodes = mutableListOf<String>()
            // Fixed times
            val times = spList("digest_times")
            times.forEach { requestCodes.add("digest_fixed_${it.hashCode()}") }
            // Interval
            requestCodes.add("digest_interval")
            // Daily
            requestCodes.add("digest_daily")
            // Weekly (all 7 days × 24 hours as safety net)
            for (d in 0..6) {
                for (h in 0..23) {
                    requestCodes.add("digest_weekly_${d}_${h}_00")
                    requestCodes.add("digest_weekly_${d}_${h}_30")
                }
            }
            requestCodes.forEach { code ->
                val intent = Intent(this, DigestReceiver::class.java).apply {
                    action = DigestReceiver.ACTION_DIGEST
                }
                val pending = PendingIntent.getBroadcast(
                    this, code.hashCode(), intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmMgr.cancel(pending)
            }
            log("info", "Cancelled digest alarms")
        } catch (e: Exception) {
            log("error", "cancelDigestAlarms failed: ${e.message}")
        }
    }

    private fun isDigestAppAllowed(pkg: String): Boolean {
        val filter = spStr("digest_app_filter", "all")
        if (filter == "all") return true
        val appList = spList("digest_app_list")
        return when (filter) {
            "include_only" -> appList.contains(pkg)
            "exclude" -> !appList.contains(pkg)
            else -> true
        }
    }

    fun flushPackage(pkg: String, isDigest: Boolean = true) {
        try {
            val group = buffer[pkg] ?: return
            val pending = group.getAllPendingNotifications()
            if (pending.isEmpty()) return
            log("info", "Flush ${if (isDigest) "digest" else "package"} for $pkg — ${pending.size} notification(s)")
            val actions = pending.flatMap { it.actions }
            val summary = if (isDigest) callAI(pkg, pending, isDigest = true) else callAI(pkg, pending)
            if (summary != null && summary.isNotBlank() && !isNoChangeResponse(summary)) {
                val appIcon = getAppIcon(pkg)
                val color = getNotificationColor(pkg)
                val notifId = group.getOrCreateNotificationId(null)
                postSummary(pkg, summary, actions, pending.size, appIcon, color, notifId)
                recordStat(pkg, intercepted = false, summarised = true)
                val processedKeys = pending.map { it.sbnKey }.toSet()
                group.clearProcessedNotifications(processedKeys)
                buffer.entries.removeAll { it.value.getAllPendingNotifications().isEmpty() }
            } else {
                log("info", "Flush for $pkg produced no summary — retaining notifications")
            }
        } catch (e: Exception) {
            log("error", "flushPackage crash: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    fun flushAllPackages() {
        log("info", "Flush all packages triggered by digest alarm")
        val scheduleType = spStr("digest_schedule_type", "fixed_times")
        buffer.keys.toList().forEach { pkg ->
            if (isDigestAppAllowed(pkg)) {
                flushPackage(pkg, isDigest = true)
            } else {
                log("info", "Skipping $pkg — excluded from digest by app filter")
            }
        }
        // Reschedule for next occurrence
        scheduleDigestAlarms()
    }

    // ── Retry Queue ──────────────────────────────────────────────────────────────

    private fun enqueueRetry(pkg: String, items: List<NotificationItem>) {
        try {
            val sp = sp()
            val key = "flutter.retry_queue"
            val arr = try { JSONArray(sp.getString(key, "[]")) } catch (_: Exception) { JSONArray() }
            val itemJson = JSONArray()
            items.forEach { itemJson.put(it.toJson()) }
            arr.put(JSONObject().apply {
                put("package", pkg)
                put("items", itemJson)
                put("attempts", 0)
                put("timestamp", System.currentTimeMillis())
            })
            // Limit queue to 20 entries
            while (arr.length() > 20) {
                arr.remove(0)
            }
            sp.edit().putString(key, arr.toString()).apply()
            log("warn", "Enqueued retry for $pkg — ${items.size} item(s). Queue size: ${arr.length()}")
        } catch (e: Exception) {
            log("error", "enqueueRetry failed: ${e.message}")
        }
    }

    fun processRetryQueue() {
        // Run retries on background executor so slow/failing AI calls
        // never block the main thread and stall new notifications.
        executor.execute {
            try {
                if (!isNetworkAvailable()) {
                    log("info", "Retry queue: no network — skipping")
                    return@execute
                }
                val sp = sp()
                val key = "flutter.retry_queue"
                val arr = try { JSONArray(sp.getString(key, "[]")) } catch (_: Exception) { JSONArray() }
                if (arr.length() == 0) return@execute
                log("info", "Processing retry queue — ${arr.length()} item(s)")
                val remaining = JSONArray()
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val pkg = obj.getString("package")
                    val itemsJson = obj.getJSONArray("items")
                    val attempts = obj.getInt("attempts") + 1
                    val items = (0 until itemsJson.length()).map { idx ->
                        NotificationItem.fromJson(itemsJson.getJSONObject(idx))
                    }
                    val summary = callAI(pkg, items)
                    if (summary != null && summary.isNotBlank() && !isNoChangeResponse(summary)) {
                        val actions = items.flatMap { it.actions }
                        val appIcon = getAppIcon(pkg)
                        val color = getNotificationColor(pkg)
                        postSummary(pkg, summary, actions, items.size, appIcon, color)
                        recordStat(pkg, intercepted = false, summarised = true)
                        log("success", "Retry succeeded for $pkg (attempt $attempts)")
                    } else if (attempts < 3) {
                        obj.put("attempts", attempts)
                        remaining.put(obj)
                        log("warn", "Retry failed for $pkg — attempt $attempts/3, requeued")
                    } else {
                        log("warn", "Retry dropped for $pkg after $attempts attempts")
                    }
                }
                sp.edit().putString(key, remaining.toString()).apply()
            } catch (e: Exception) {
                log("error", "processRetryQueue crash: ${e.javaClass.simpleName}: ${e.message}")
            }
        }
    }

    private fun isNetworkAvailable(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val activeNetwork = cm.activeNetworkInfo
            activeNetwork?.isConnected == true
        } catch (_: Exception) { false }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun getCurrentWifiSsid(): String? {
        return try {
            val wifiManager = getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
            val info = wifiManager.connectionInfo
            val ssid = info.ssid?.replace("\"", "")?.trim()
            if (ssid != null && ssid.isNotEmpty() && ssid != "<unknown ssid>" && ssid != "0x") {
                ssid
            } else {
                null
            }
        } catch (e: Exception) {
            log("warn", "Could not read WiFi SSID: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    private fun appName(pkg: String) = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg.split(".").last().replaceFirstChar { it.uppercase() } }
}
