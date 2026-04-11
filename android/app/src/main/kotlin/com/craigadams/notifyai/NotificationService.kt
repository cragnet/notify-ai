package com.craigadams.notifyai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
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

        val enabledApps = prefs.getStringSet("flutter.enabled_apps_set", null)
        if (enabledApps != null && enabledApps.isNotEmpty() && !enabledApps.contains(packageName)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: return
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
        if (text.length < 3) return

        val actions = sbn.notification.actions?.toList() ?: emptyList()

        recordStat(prefs, packageName, intercepted = true, summarised = false)

        if (!messageBuffer.containsKey(packageName)) {
            messageBuffer[packageName] = mutableListOf()
        }
        messageBuffer[packageName]?.add(BufferedNotification(title, text, actions, sbn.key))

        val threshold = prefs.getInt("flutter.notification_threshold", 2)
        debounceHandlers[packageName]?.let { handler.removeCallbacks(it) }
        val delayMs = if (threshold == 1) 1500L else DEBOUNCE_MS

        val runnable = Runnable {
            val buffered = messageBuffer[packageName]?.toList() ?: return@Runnable
            val currentThreshold = prefs.getInt("flutter.notification_threshold", 2)
            if (buffered.size < currentThreshold) return@Runnable

            messageBuffer.remove(packageName)
            debounceHandlers.remove(packageName)

            try { buffered.forEach { try { cancelNotification(it.sbnKey) } catch (_: Exception) {} } } catch (_: Exception) {}

            executor.execute {
                val summary = getSummaryFromAI(prefs, packageName, buffered)
                if (summary != null) {
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
        val model = prefs.getString("flutter.model_$provider", defaultModel(provider)) ?: defaultModel(provider)
        val baseUrl = prefs.getString("flutter.base_url_$provider", defaultBaseUrl(provider)) ?: defaultBaseUrl(provider)
        val summaryLength = prefs.getInt("flutter.summary_length", 2)

        val lengthHint = when (summaryLength) {
            1 -> "in one very brief sentence (max 10 words)"
            3 -> "in 2-3 sentences with key details"
            else -> "in one clear sentence"
        }

        val appName = appName(packageName)
        val msgs = buffered.joinToString("\n") { "• ${it.title}: ${it.text}" }
        val prompt = "Summarise these $appName messages $lengthHint. Be direct, no preamble:\n\n$msgs"

        return try {
            when (provider) {
                "claude" -> callClaude(apiKey, model, prompt, baseUrl)
                "openai" -> callOpenAICompat(apiKey, model, prompt, baseUrl)
                "openrouter" -> callOpenAICompat(apiKey, model, prompt, "https://openrouter.ai", extraHeaders = mapOf("HTTP-Referer" to "com.craigadams.notifyai"))
                "gemini" -> callGemini(apiKey, model, prompt)
                "gemini_nano" -> null // on-device — not yet implemented
                "ollama" -> callOllama(baseUrl, model, prompt, apiKey)
                "local" -> callOpenAICompat(apiKey, model, prompt, baseUrl)
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "AI error [$provider]: ${e.message}")
            null
        }
    }

    // Claude uses its own API format
    private fun callClaude(apiKey: String, model: String, prompt: String, baseUrl: String): String? {
        if (apiKey.isEmpty()) { Log.w(TAG, "Claude: no API key"); return null }
        val url = URL("${baseUrl.trimEnd('/')}/v1/messages")
        val body = """{"model":"$model","max_tokens":150,"messages":[{"role":"user","content":"${esc(prompt)}"}]}"""
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

    // OpenAI-compatible — works for OpenAI, OpenRouter, Local servers
    private fun callOpenAICompat(
        apiKey: String,
        model: String,
        prompt: String,
        baseUrl: String,
        extraHeaders: Map<String, String> = emptyMap()
    ): String? {
        val url = URL("${baseUrl.trimEnd('/')}/v1/chat/completions")
        val body = """{"model":"$model","max_tokens":150,"messages":[{"role":"user","content":"${esc(prompt)}"}]}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            if (apiKey.isNotEmpty()) setRequestProperty("Authorization", "Bearer $apiKey")
            extraHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
            connectTimeout = 15000; readTimeout = 30000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").getString("content").trim()
        }
        Log.e(TAG, "OpenAI-compat ${conn.responseCode}: ${conn.errorStream?.bufferedReader()?.readText()}")
        return null
    }

    // Ollama uses its own /api/generate endpoint
    private fun callOllama(baseUrl: String, model: String, prompt: String, apiKey: String): String? {
        if (baseUrl.isEmpty()) { Log.w(TAG, "Ollama: no URL configured"); return null }
        val url = URL("${baseUrl.trimEnd('/')}/api/generate")
        val body = """{"model":"$model","prompt":"${esc(prompt)}","stream":false}"""
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            if (apiKey.isNotEmpty()) setRequestProperty("Authorization", "Bearer $apiKey")
            connectTimeout = 30000; readTimeout = 120000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText()).getString("response").trim()
        }
        Log.e(TAG, "Ollama ${conn.responseCode}: ${conn.errorStream?.bufferedReader()?.readText()}")
        return null
    }

    private fun callGemini(apiKey: String, model: String, prompt: String): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey")
        val body = """{"contents":[{"parts":[{"text":"${esc(prompt)}"}]}],"generationConfig":{"maxOutputTokens":150}}"""
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

    private fun postSummaryNotification(
        packageName: String,
        summary: String,
        actions: List<Notification.Action>,
        count: Int
    ) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val groupId = "notify_ai_group_$packageName"
        val channelId = "notify_ai_$packageName"
        val name = appName(packageName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannelGroup(NotificationChannelGroup(groupId, name))
            val ch = NotificationChannel(channelId, "$name Summaries", NotificationManager.IMPORTANCE_DEFAULT)
            ch.group = groupId
            nm.createNotificationChannel(ch)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }

        val countText = if (count > 1) "$count messages · " else ""
        builder.setContentTitle("$name · AI Summary")
            .setContentText(summary)
            .setStyle(Notification.BigTextStyle().bigText(summary).setSummaryText("${countText}AI summary"))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setGroup(groupId)

        actions.take(3).forEach { action ->
            try { builder.addAction(action) } catch (_: Exception) {}
        }

        nm.notify("$packageName:summary".hashCode(), builder.build())
        Log.d(TAG, "Posted summary for $name")
    }

    private fun recordStat(
        prefs: android.content.SharedPreferences,
        packageName: String,
        intercepted: Boolean,
        summarised: Boolean
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val key = "flutter.stats_${packageName}_$today"
        val obj = try { JSONObject(prefs.getString(key, "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        if (intercepted) obj.put("intercepted", obj.optInt("intercepted", 0) + 1)
        if (summarised) obj.put("summarised", obj.optInt("summarised", 0) + 1)
        prefs.edit().putString(key, obj.toString()).apply()

        val allKeysKey = "flutter.stats_all_keys"
        val arr = try { JSONArray(prefs.getString(allKeysKey, "[]")) } catch (_: Exception) { JSONArray() }
        var found = false
        for (i in 0 until arr.length()) { if (arr.getString(i) == key) { found = true; break } }
        if (!found) { arr.put(key); prefs.edit().putString(allKeysKey, arr.toString()).apply() }
    }

    private fun appName(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName.split(".").last().replaceFirstChar { it.uppercase() }
        }
    }

    private fun defaultModel(provider: String) = when (provider) {
        "claude" -> "claude-haiku-4-5-20251001"
        "openai" -> "gpt-4o-mini"
        "ollama" -> "llama3.2:3b"
        "openrouter" -> "anthropic/claude-haiku-4-5"
        "gemini" -> "gemini-2.0-flash"
        "gemini_nano" -> "gemini-nano"
        "local" -> ""
        else -> ""
    }

    private fun defaultBaseUrl(provider: String) = when (provider) {
        "claude" -> "https://api.anthropic.com"
        "openai" -> "https://api.openai.com"
        "openrouter" -> "https://openrouter.ai"
        else -> ""
    }

    private fun esc(text: String) = text
        .replace("\\", "\\\\").replace("\"", "\\\"")
        .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}
