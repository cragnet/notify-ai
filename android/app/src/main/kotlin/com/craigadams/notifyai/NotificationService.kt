package com.craigadams.notifyai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
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
        val sbnKey: String,
        val imageBase64: String? = null
    )

    private val messageBuffer = mutableMapOf<String, MutableList<BufferedNotification>>()
    private val debounceHandlers = mutableMapOf<String, Runnable>()
    private val DEBOUNCE_MS = 4000L

    // ── Lifecycle ──────────────────────────────────────────────────────────────

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

        val appName = appName(packageName)

        // Extract image if present
        val imageBase64 = extractImageFromNotification(sbn.notification)

        val actions = sbn.notification.actions?.toList() ?: emptyList()

        appendLog(prefs, "info", "Intercepted from $appName: \"$title\"${if (imageBase64 != null) " [+image]" else ""}")

        // Save to 30-day history
        saveToHistory(prefs, packageName, appName, title, text, imageBase64 != null)

        // Record stat
        recordStat(prefs, packageName, intercepted = true, summarised = false)

        if (!messageBuffer.containsKey(packageName)) {
            messageBuffer[packageName] = mutableListOf()
        }
        messageBuffer[packageName]?.add(BufferedNotification(title, text, actions, sbn.key, imageBase64))

        val threshold = prefs.getInt("flutter.notification_threshold", 2)
        val buffered = messageBuffer[packageName]?.size ?: 0

        appendLog(prefs, "info", "Buffered $buffered/${threshold} from $appName")

        debounceHandlers[packageName]?.let { handler.removeCallbacks(it) }
        val delayMs = if (threshold == 1) 1500L else DEBOUNCE_MS

        val runnable = Runnable {
            val buf = messageBuffer[packageName]?.toList() ?: return@Runnable
            val currentThreshold = prefs.getInt("flutter.notification_threshold", 2)

            if (buf.size < currentThreshold) {
                appendLog(prefs, "info", "Waiting for more from $appName (${buf.size}/$currentThreshold)")
                return@Runnable
            }

            messageBuffer.remove(packageName)
            debounceHandlers.remove(packageName)

            appendLog(prefs, "info", "Threshold met — sending ${buf.size} notifications from $appName to AI")

            // Dismiss originals if setting is on
            val dismissOriginals = prefs.getBoolean("flutter.dismiss_on_app_usage", true)
            if (dismissOriginals) {
                buf.forEach { bn ->
                    try { cancelNotification(bn.sbnKey) } catch (_: Exception) {}
                }
                appendLog(prefs, "info", "Dismissed ${buf.size} original notification(s) from $appName")
            }

            executor.execute {
                val summary = getSummaryFromAI(prefs, packageName, buf)
                if (summary != null) {
                    val allActions = buf.flatMap { it.actions }.distinctBy { it.title?.toString() }
                    postSummaryNotification(packageName, summary, allActions, buf.size, prefs)
                    recordStat(prefs, packageName, intercepted = false, summarised = true)
                    appendLog(prefs, "success", "Summary posted for $appName: \"${summary.take(80)}${if (summary.length > 80) "…" else ""}\"")
                } else {
                    appendLog(prefs, "error", "AI returned no summary for $appName — check provider settings and API key")
                }
            }
        }

        debounceHandlers[packageName] = runnable
        handler.postDelayed(runnable, delayMs)
    }

    // ── AI dispatch ────────────────────────────────────────────────────────────

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

        // Check if any notification has an image and provider supports multimodal
        val images = buffered.mapNotNull { it.imageBase64 }
        val supportsMultimodal = supportsMultimodal(provider, model)

        appendLog(prefs, "info", "Calling $provider (${model.take(30)})${if (images.isNotEmpty() && supportsMultimodal) " with ${images.size} image(s)" else ""}")

        return try {
            when (provider) {
                "claude" -> callClaude(apiKey, model, prompt, baseUrl, if (supportsMultimodal) images else emptyList())
                "openai" -> callOpenAICompat(apiKey, model, prompt, baseUrl, if (supportsMultimodal) images else emptyList())
                "openrouter" -> callOpenAICompat(apiKey, model, prompt, "https://openrouter.ai", if (supportsMultimodal) images else emptyList(), extraHeaders = mapOf("HTTP-Referer" to "com.craigadams.notifyai"))
                "gemini" -> callGemini(apiKey, model, prompt, if (supportsMultimodal) images else emptyList())
                "ollama" -> callOllama(baseUrl, model, prompt, apiKey)
                "local" -> callOpenAICompat(apiKey, model, prompt, baseUrl)
                "gemini_nano" -> { appendLog(prefs, "warn", "Gemini Nano on-device not yet implemented"); null }
                else -> null
            }
        } catch (e: Exception) {
            appendLog(prefs, "error", "AI call failed [$provider]: ${e.message}")
            null
        }
    }

    private fun supportsMultimodal(provider: String, model: String): Boolean {
        return when (provider) {
            "claude" -> true // All Claude models support vision
            "openai" -> model.contains("gpt-4") || model.contains("gpt-4o")
            "gemini" -> true
            "openrouter" -> model.contains("claude") || model.contains("gpt-4o") || model.contains("gemini")
            else -> false
        }
    }

    // ── API callers ────────────────────────────────────────────────────────────

    private fun callClaude(
        apiKey: String, model: String, prompt: String,
        baseUrl: String, images: List<String> = emptyList()
    ): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("${baseUrl.trimEnd('/')}/v1/messages")

        // Build content array — images first, then text
        val contentArr = JSONArray()
        images.forEach { b64 ->
            contentArr.put(JSONObject().apply {
                put("type", "image")
                put("source", JSONObject().apply {
                    put("type", "base64")
                    put("media_type", "image/jpeg")
                    put("data", b64)
                })
            })
        }
        contentArr.put(JSONObject().apply {
            put("type", "text")
            put("text", prompt)
        })

        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 150)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", contentArr)
            }))
        }.toString()

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("x-api-key", apiKey)
            setRequestProperty("anthropic-version", "2023-06-01")
            connectTimeout = 20000; readTimeout = 40000; doOutput = true
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }

        if (conn.responseCode == 200) {
            return JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("content").getJSONObject(0).getString("text").trim()
        }
        Log.e(TAG, "Claude ${conn.responseCode}: ${conn.errorStream?.bufferedReader()?.readText()}")
        return null
    }

    private fun callOpenAICompat(
        apiKey: String, model: String, prompt: String, baseUrl: String,
        images: List<String> = emptyList(),
        extraHeaders: Map<String, String> = emptyMap()
    ): String? {
        val url = URL("${baseUrl.trimEnd('/')}/v1/chat/completions")

        val contentArr = JSONArray()
        // Add images if present
        images.forEach { b64 ->
            contentArr.put(JSONObject().apply {
                put("type", "image_url")
                put("image_url", JSONObject().apply {
                    put("url", "data:image/jpeg;base64,$b64")
                })
            })
        }
        contentArr.put(JSONObject().apply {
            put("type", "text")
            put("text", prompt)
        })

        val messagesArr = JSONArray().put(JSONObject().apply {
            put("role", "user")
            put("content", if (images.isEmpty()) prompt else contentArr)
        })

        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 150)
            put("messages", messagesArr)
        }.toString()

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            if (apiKey.isNotEmpty()) setRequestProperty("Authorization", "Bearer $apiKey")
            extraHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
            connectTimeout = 20000; readTimeout = 40000; doOutput = true
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

    private fun callGemini(
        apiKey: String, model: String, prompt: String,
        images: List<String> = emptyList()
    ): String? {
        if (apiKey.isEmpty()) return null
        val url = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey")

        val partsArr = JSONArray()
        images.forEach { b64 ->
            partsArr.put(JSONObject().apply {
                put("inline_data", JSONObject().apply {
                    put("mime_type", "image/jpeg")
                    put("data", b64)
                })
            })
        }
        partsArr.put(JSONObject().apply { put("text", prompt) })

        val body = JSONObject().apply {
            put("contents", JSONArray().put(JSONObject().apply {
                put("parts", partsArr)
            }))
            put("generationConfig", JSONObject().apply { put("maxOutputTokens", 150) })
        }.toString()

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 20000; readTimeout = 40000; doOutput = true
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

    private fun callOllama(baseUrl: String, model: String, prompt: String, apiKey: String): String? {
        if (baseUrl.isEmpty()) return null
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
        return null
    }

    // ── Notification posting ───────────────────────────────────────────────────

    private fun postSummaryNotification(
        packageName: String,
        summary: String,
        actions: List<Notification.Action>,
        count: Int,
        prefs: android.content.SharedPreferences
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

        val retainActions = prefs.getBoolean("flutter.retain_original_actions", true)
        if (retainActions) {
            actions.take(3).forEach { action ->
                try { builder.addAction(action) } catch (_: Exception) {}
            }
        }

        nm.notify("$packageName:summary".hashCode(), builder.build())
    }

    // ── Image extraction ───────────────────────────────────────────────────────

    private fun extractImageFromNotification(notification: Notification): String? {
        return try {
            val extras = notification.extras

            // Try EXTRA_PICTURE first (big picture style notifications)
            val picture = extras.getParcelable<android.graphics.Bitmap>(Notification.EXTRA_PICTURE)
            if (picture != null) {
                return bitmapToBase64(picture)
            }

            // Try large icon
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val largeIcon = extras.getParcelable<Icon>(Notification.EXTRA_LARGE_ICON)
                if (largeIcon != null) {
                    val drawable = largeIcon.loadDrawable(this)
                    if (drawable is BitmapDrawable) {
                        return bitmapToBase64(drawable.bitmap)
                    }
                }
            }

            null
        } catch (e: Exception) {
            Log.w(TAG, "Could not extract image: ${e.message}")
            null
        }
    }

    private fun bitmapToBase64(bitmap: Bitmap): String? {
        return try {
            // Scale down to max 512px on longest side to keep payload reasonable
            val maxDim = 512
            val scaled = if (bitmap.width > maxDim || bitmap.height > maxDim) {
                val ratio = bitmap.width.toFloat() / bitmap.height.toFloat()
                val (w, h) = if (bitmap.width > bitmap.height) {
                    Pair(maxDim, (maxDim / ratio).toInt())
                } else {
                    Pair((maxDim * ratio).toInt(), maxDim)
                }
                Bitmap.createScaledBitmap(bitmap, w, h, true)
            } else {
                bitmap
            }

            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.w(TAG, "Bitmap to base64 failed: ${e.message}")
            null
        }
    }

    // ── Logging ────────────────────────────────────────────────────────────────

    private fun appendLog(
        prefs: android.content.SharedPreferences,
        level: String,
        message: String
    ) {
        Log.d(TAG, "[$level] $message")
        try {
            val key = "service_log"
            val existing = prefs.getString(key, "[]") ?: "[]"
            val arr = try { JSONArray(existing) } catch (_: Exception) { JSONArray() }

            val ts = SimpleDateFormat("HH:mm:ss dd/MM", Locale.getDefault()).format(Date())
            val entry = JSONObject().apply {
                put("timestamp", ts)
                put("level", level)
                put("message", message)
            }

            arr.put(entry)

            // Keep last 500 entries
            val trimmed = JSONArray()
            val start = maxOf(0, arr.length() - 500)
            for (i in start until arr.length()) trimmed.put(arr.get(i))

            prefs.edit().putString(key, trimmed.toString()).apply()
        } catch (e: Exception) {
            Log.w(TAG, "Log write failed: ${e.message}")
        }
    }

    // ── History ────────────────────────────────────────────────────────────────

    private fun saveToHistory(
        prefs: android.content.SharedPreferences,
        packageName: String,
        appName: String,
        title: String,
        message: String,
        hadImage: Boolean
    ) {
        try {
            val key = "notification_history"
            val existing = prefs.getString(key, "[]") ?: "[]"
            val arr = try { JSONArray(existing) } catch (_: Exception) { JSONArray() }

            val ts = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            arr.put(JSONObject().apply {
                put("packageName", packageName)
                put("appName", appName)
                put("title", title)
                put("message", message)
                put("timestamp", ts)
                put("hadImage", hadImage)
            })

            // Prune entries older than 30 days
            val cutoff = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
            val cutoffStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(cutoff))
            val pruned = JSONArray()
            for (i in 0 until arr.length()) {
                try {
                    val obj = arr.getJSONObject(i)
                    val objDate = obj.getString("timestamp").substring(0, 10)
                    if (objDate >= cutoffStr) pruned.put(obj)
                } catch (_: Exception) {}
            }

            prefs.edit().putString(key, pruned.toString()).apply()
        } catch (e: Exception) {
            Log.w(TAG, "History write failed: ${e.message}")
        }
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

    // ── Helpers ────────────────────────────────────────────────────────────────

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
