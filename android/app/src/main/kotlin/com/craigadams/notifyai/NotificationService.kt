package com.craigadams.notifyai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import org.json.JSONArray
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class NotificationService : NotificationListenerService() {

    private val TAG = "NotifyAI"
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    // Buffer per app: packageName -> list of buffered notifications
    data class BufferedNotification(
        val title: String,
        val text: String,
        val actions: List<Notification.Action>,
        val sbnKey: String
    )

    private val messageBuffer = mutableMapOf<String, MutableList<BufferedNotification>>()
    private val debounceHandlers = mutableMapOf<String, Runnable>()
    private val DEBOUNCE_MS = 4000L

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        if (!prefs.getBoolean("flutter.service_enabled", true)) return

        val packageName = sbn.packageName
        if (packageName == applicationContext.packageName) return

        // Check enabled apps
        val enabledAppsSet = prefs.getStringSet("flutter.enabled_apps_set", null)
        if (enabledAppsSet != null && enabledAppsSet.isNotEmpty() && !enabledAppsSet.contains(packageName)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: return
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
        if (text.length < 3) return

        // Capture actions from the original notification
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        Log.d(TAG, "Buffering from $packageName [$title]: $text (${actions.size} actions)")

        // Record interception in stats
        recordStat(prefs, packageName, intercepted = true, summarised = false)

        if (!messageBuffer.containsKey(packageName)) {
            messageBuffer[packageName] = mutableListOf()
        }
        messageBuffer[packageName]?.add(
            BufferedNotification(title, text, actions, sbn.key)
        )

        val threshold = prefs.getInt("flutter.notification_threshold", 2)

        debounceHandlers[packageName]?.let { handler.removeCallbacks(it) }

        val delayMs = if (threshold == 1) 1500L else DEBOUNCE_MS

        val runnable = Runnable {
            val buffered = messageBuffer[packageName]?.toList() ?: return@Runnable
            val currentThreshold = prefs.getInt("flutter.notification_threshold", 2)

            if (buffered.size < currentThreshold) return@Runnable

            messageBuffer.remove(packageName)
            debounceHandlers.remove(packageName)

            Log.d(TAG, "Processing ${buffered.size} notifications from $packageName")

            // Cancel the original notifications
            try {
                buffered.forEach { bn ->
                    try { cancelNotification(bn.sbnKey) } catch (e: Exception) { }
                }
            } catch (e: Exception) { }

            executor.execute {
                val summary = getSummaryFromAI(prefs, packageName, buffered)
                if (summary != null) {
                    // Collect all unique actions from buffered notifications
                    val allActions = buffered.flatMap { it.actions }.distinctBy { it.title?.toString() }
                    postSummaryNotification(packageName, summary, allActions, buffered.size)
                    recordStat(prefs, packageName, intercepted = false, summarised = true)
                }
            }
        }

        debounceHandlers[packageName] = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun getSummaryFromAI(
        prefs: android.content.SharedPreferences,
        packageName: String,
        buffered: List<BufferedNotification>
    ): String? {
        val provider = prefs.getString("flutter.ai_provider", "claude") ?: "claude"
        val apiKey = prefs.getString("flutter.api_key_$provider", "") ?: ""
        val model = prefs.getString("flutter.model_$provider", getDefaultModel(provider)) ?: getDefaultModel(provider)
        val baseUrl = prefs.getString("flutter.base_url_$provider", getDefaultBaseUrl(provider)) ?: getDefaultBaseUrl(provider)
        val summaryLength = prefs.getInt("flutter.summary_length", 2)

        val lengthInstruction = when (summaryLength) {
            1 -> "in one very brief sentence (max 10 words)"
            3 -> "in 2-3 sentences with key details"
            else -> "in one clear sentence"
        }

        val appName = getAppName(packageName)
        val messagesText = buffered.joinToString("\n") { "• ${it.title}: ${it.text}" }
        val prompt = "Summarise these $appName messages $lengthInstruction. Be direct, no preamble:\n\n$messagesText"

        return try {
            when (provider) {
                "claude" -> callClaude(apiKey, model, prompt, baseUrl)
                "openai" -> callOpenAI(apiKey, model, prompt, baseUrl)
                "ollama" -> callOllama(baseUrl.ifEmpty { "http://10.0.1.33:11434" }, model, prompt)
                "openrouter" -> callOpenRouter(apiKey, model, prompt)
                "gemini" -> callGemini(apiKey, model, prompt)
                "gemini_nano" -> callGeminiNano(prompt)
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "AI error [$provider]: ${e.message}")
            null
        }
    }

    private fun callClaude(apiKey: String, model: String, prompt: String, baseUrl: String): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("${baseUrl.trimEnd('/')}/v1/messages")
        val body = """{"model":"$model","max_tokens":150,"messages":[{"role":"user","content":"${escapeJson(prompt)}"}]}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("x-api-key", apiKey)
            setRequestProperty("anthropic-version", "2023-06-01")
            connectTimeout = 15000; readTimeout = 30000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("content").getJSONObject(0).getString("text").trim()
        }
        Log.e(TAG, "Claude ${conn.responseCode}: ${conn.errorStream?.bufferedReader()?.readText()}")
        return null
    }

    private fun callOpenAI(apiKey: String, model: String, prompt: String, baseUrl: String): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("${baseUrl.trimEnd('/')}/v1/chat/completions")
        val body = """{"model":"$model","max_tokens":150,"messages":[{"role":"user","content":"${escapeJson(prompt)}"}]}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $apiKey")
            connectTimeout = 15000; readTimeout = 30000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").getString("content").trim()
        }
        return null
    }

    private fun callOllama(baseUrl: String, model: String, prompt: String): String? {
        val url = URL("${baseUrl.trimEnd('/')}/api/generate")
        val body = """{"model":"$model","prompt":"${escapeJson(prompt)}","stream":false}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 30000; readTimeout = 120000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText()).getString("response").trim()
        }
        return null
    }

    private fun callOpenRouter(apiKey: String, model: String, prompt: String): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("https://openrouter.ai/api/v1/chat/completions")
        val body = """{"model":"$model","max_tokens":150,"messages":[{"role":"user","content":"${escapeJson(prompt)}"}]}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $apiKey")
            setRequestProperty("HTTP-Referer", "com.craigadams.notifyai")
            connectTimeout = 15000; readTimeout = 30000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").getString("content").trim()
        }
        return null
    }

    private fun callGemini(apiKey: String, model: String, prompt: String): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey")
        val body = """{"contents":[{"parts":[{"text":"${escapeJson(prompt)}"}]}],"generationConfig":{"maxOutputTokens":150}}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 15000; readTimeout = 30000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts")
                .getJSONObject(0).getString("text").trim()
        }
        return null
    }

    private fun callGeminiNano(prompt: String): String? {
        // Gemini Nano on-device via Google AI Edge SDK
        // This requires the google-ai-edge dependency and device support
        // Fallback: return null if not available (will be handled gracefully in UI)
        Log.w(TAG, "Gemini Nano on-device inference not yet implemented in this build")
        return null
    }

    private fun postSummaryNotification(
        packageName: String,
        summary: String,
        actions: List<Notification.Action>,
        count: Int
    ) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val groupId = "notify_ai_group_$packageName"
        val channelId = "notify_ai_$packageName"
        val appName = getAppName(packageName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Create a channel group per app
            nm.createNotificationChannelGroup(
                NotificationChannelGroup(groupId, appName)
            )
            val channel = NotificationChannel(
                channelId,
                "$appName Summaries",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                group = groupId
                description = "AI summaries from $appName"
            }
            nm.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val countText = if (count > 1) "$count messages · " else ""

        builder
            .setContentTitle("$appName · AI Summary")
            .setContentText(summary)
            .setStyle(Notification.BigTextStyle()
                .bigText(summary)
                .setSummaryText("${countText}AI summary"))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setGroup(groupId)

        // Re-attach original notification actions
        actions.take(3).forEach { action ->
            try {
                builder.addAction(action)
            } catch (e: Exception) {
                Log.w(TAG, "Could not re-attach action: ${action.title}")
            }
        }

        nm.notify("$packageName:summary".hashCode(), builder.build())
        Log.d(TAG, "Posted summary for $appName: $summary")
    }

    // ── Stats ──────────────────────────────────────────────────────────────────

    private fun recordStat(
        prefs: android.content.SharedPreferences,
        packageName: String,
        intercepted: Boolean,
        summarised: Boolean
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val key = "flutter.stats_${packageName}_$today"
        val existing = prefs.getString(key, null)
        val obj = if (existing != null) JSONObject(existing) else JSONObject()

        if (intercepted) obj.put("intercepted", obj.optInt("intercepted", 0) + 1)
        if (summarised) obj.put("summarised", obj.optInt("summarised", 0) + 1)

        prefs.edit().putString(key, obj.toString()).apply()

        // Also update the list of known stat keys so Flutter can discover them
        val allKeysKey = "flutter.stats_all_keys"
        val allKeysJson = prefs.getString(allKeysKey, "[]")
        val allKeys = JSONArray(allKeysJson)
        var found = false
        for (i in 0 until allKeys.length()) {
            if (allKeys.getString(i) == key) { found = true; break }
        }
        if (!found) {
            allKeys.put(key)
            prefs.edit().putString(allKeysKey, allKeys.toString()).apply()
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun getAppName(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            packageName.split(".").last().replaceFirstChar { it.uppercase() }
        }
    }

    private fun getDefaultModel(provider: String) = when (provider) {
        "claude" -> "claude-haiku-4-5-20251001"
        "openai" -> "gpt-4o-mini"
        "ollama" -> "llama3.2:3b"
        "openrouter" -> "anthropic/claude-haiku-4-5"
        "gemini" -> "gemini-2.0-flash"
        "gemini_nano" -> "gemini-nano"
        else -> ""
    }

    private fun getDefaultBaseUrl(provider: String) = when (provider) {
        "claude" -> "https://api.anthropic.com"
        "openai" -> "https://api.openai.com"
        "ollama" -> "http://10.0.1.33:11434"
        else -> ""
    }

    private fun escapeJson(text: String) = text
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}
