package com.craigadams.notifyai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
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

class NotificationService : NotificationListenerService() {

    private val TAG = "NotifyAI"
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    data class NotificationItem(
        val title: String,
        val text: String,
        val actions: List<Notification.Action>,
        val sbnKey: String,
        val imageBase64: String? = null,
        val timestamp: Long = System.currentTimeMillis(),
        val conversationId: String? = null
    )

    data class NotificationGroup(
        val notifications: MutableList<NotificationItem> = mutableListOf(),
        var summary: String? = null,
        var summaryTimestamp: Long = 0,
        var notificationColor: Int? = null
    )

    // Per-package buffer for grouped notifications
    private val buffer = mutableMapOf<String, NotificationGroup>()
    private val debounce = mutableMapOf<String, Runnable>()
    private val DEBOUNCE_MS = 3000L
    private val STATUS_NOTIF_ID = "notifyai_status".hashCode()

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
        log("success", "=== Listener CONNECTED ===")

        // Elevate to foreground service so OS doesn't kill this process
        startForegroundCompat()

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
        log("warn", "Listener DISCONNECTED — requesting rebind")
        postStatusNotification("Notify AI reconnecting…", "Service was disconnected — reconnecting automatically")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestRebind(android.content.ComponentName(this, NotificationService::class.java))
        }
    }

    // ── onNotificationPosted ───────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            handleNotification(sbn)
        } catch (e: Exception) {
            log("error", "onNotificationPosted crash: ${e.javaClass.simpleName}: ${e.message}")
        }
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

    private fun _handleNotificationInternal(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        if (pkg == applicationContext.packageName) return

        log("info", "--- Notification from: $pkg ---")

        if (!spBool("service_enabled", true)) { log("info", "Service disabled"); return }

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) { log("warn", "No apps selected"); return }
        if (!selected.contains(pkg)) { log("info", "$pkg not selected — skipping"); return }

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

        // Extract conversation info for grouping
        val conversationId = extractConversationId(extras, title)
        val name = appName(pkg)
        val image = extractImage(sbn.notification)
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        saveHistory(pkg, name, title, text, image != null)
        recordStat(pkg, intercepted = true, summarised = false)

        // Get or create the notification group for this package
        val group = buffer.getOrPut(pkg) { NotificationGroup() }

        // Check if this is an update to an existing notification (same key)
        val existingIndex = group.notifications.indexOfFirst { it.sbnKey == sbn.key }
        val newItem = NotificationItem(
            title = title,
            text = text,
            actions = actions,
            sbnKey = sbn.key,
            imageBase64 = image,
            timestamp = System.currentTimeMillis(),
            conversationId = conversationId
        )

        if (existingIndex >= 0) {
            // Update existing notification
            group.notifications[existingIndex] = newItem
            log("info", "Updated existing notification #$existingIndex for $name")
        } else {
            // Add new notification
            group.notifications.add(newItem)
            log("info", "Added new notification to group for $name")
        }

        // Get notification color if set
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            sbn.notification.color.takeIf { it != 0 }?.let {
                group.notificationColor = it
            }
        }

        val threshold = spInt("notification_threshold", 2)
        val count = group.notifications.size
        log("info", "CAPTURED #$count from $name: title='$title' text='${text.take(80)}' threshold=$threshold conversation=$conversationId")

        // Cancel any pending debounce for this app
        debounce[pkg]?.let { handler.removeCallbacks(it) }

        val runnable = Runnable {
            val currentGroup = buffer[pkg] ?: return@Runnable
            val notificationsToProcess = currentGroup.notifications.toList()
            if (notificationsToProcess.isEmpty()) return@Runnable

            // Clear only the notifications we're processing, keep the group for future updates
            currentGroup.notifications.clear()
            debounce.remove(pkg)

            log("info", "Processing ${notificationsToProcess.size} notification(s) from $name")

            // Collect all actions from all notifications
            val allActions = notificationsToProcess.flatMap { it.actions }.distinctBy { it.title?.toString() }

            // Only dismiss the specific notifications being processed, not all from the app
            if (spBool("dismiss_on_app_usage", true)) {
                notificationsToProcess.forEach { item ->
                    try {
                        cancelNotification(item.sbnKey)
                        log("info", "Dismissed notification: ${item.sbnKey}")
                    } catch (_: Exception) {}
                }
            }

            executor.execute {
                // Build prompt with previous summary context if available
                val previousSummary = currentGroup.summary
                val summary = callAI(pkg, notificationsToProcess, previousSummary)

                if (summary != null) {
                    // Store the summary for future updates
                    currentGroup.summary = summary
                    currentGroup.summaryTimestamp = System.currentTimeMillis()

                    val appIcon = getAppIcon(pkg)
                    val notificationColor = currentGroup.notificationColor ?: getNotificationColor(pkg)
                    postSummary(pkg, summary, allActions, notificationsToProcess.size, appIcon, notificationColor)
                    recordStat(pkg, intercepted = false, summarised = true)
                    log("success", "AI summary posted for $name: \"${summary.take(100)}\"")
                } else {
                    log("error", "No AI summary for $name — check provider/key/model in Settings")
                }
            }
        }

        debounce[pkg] = runnable
        if (count >= threshold) {
            // Threshold reached — fire after short delay to let any same-burst notifications land
            handler.postDelayed(runnable, 800L)
            log("info", "Threshold met ($count >= $threshold) — triggering in 800ms")
        } else {
            // Below threshold — wait longer for more notifications
            handler.postDelayed(runnable, DEBOUNCE_MS)
            log("info", "Below threshold ($count/$threshold) — waiting ${DEBOUNCE_MS}ms for more")
        }
    }

    private fun extractConversationId(extras: android.os.Bundle, title: String): String? {
        return try {
            // Try to get conversation title/sender from messaging style
            extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
                ?: extras.getCharSequence("android.messagingStyleUser.displayName")?.toString()
                ?: title.takeIf { it.contains(":") }?.substringBefore(":")?.trim()
                ?: title
        } catch (_: Exception) { null }
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

    private fun callAI(pkg: String, buf: List<NotificationItem>, previousSummary: String? = null): String? {
        val provider = spStr("ai_provider", "ollama")
        val apiKey  = spStr("api_key_$provider", "")
        val model   = spStr("model_$provider", "")
        val baseUrl = spStr("base_url_$provider", "")
        val length  = spInt("summary_length", 2)

        log("info", "AI call: provider=$provider model=${model.ifEmpty { "(none)" }} url=${baseUrl.ifEmpty { "(default)" }} hasKey=${apiKey.isNotEmpty()} msgs=${buf.size} hasPrevious=${previousSummary != null}")

        if (model.isEmpty() && provider != "gemini_nano") {
            log("error", "AI SKIP: no model set for $provider — configure in AI Provider settings"); return null
        }
        if (provider == "ollama" && baseUrl.isEmpty()) {
            log("error", "AI SKIP: no URL set for Ollama — configure in AI Provider settings"); return null
        }
        if (provider == "gemini" && apiKey.isEmpty()) {
            log("error", "AI SKIP: no API key set for Gemini — configure in AI Provider settings"); return null
        }

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
        val msgs = buf.joinToString("\n") { "• ${it.title}: ${it.text}" }
        val customPrompt = spStr("custom_prompt", "")

        // Build prompt with previous summary context and length instruction
        val prompt = if (customPrompt.isNotEmpty()) {
            // Include length instruction in custom prompt if it doesn't already specify length
            val promptWithLength = if (customPrompt.contains("length", ignoreCase = true) ||
                                         customPrompt.contains("brief", ignoreCase = true) ||
                                         customPrompt.contains("detailed", ignoreCase = true) ||
                                         customPrompt.contains("sentence", ignoreCase = true)) {
                customPrompt
            } else {
                "$customPrompt\n\nLength requirement: $lengthInstruction"
            }

            val basePrompt = promptWithLength
                .replace("{app_name}", name)
                .replace("{notifications}", msgs)
                .replace("{count}", buf.size.toString())

            // Include previous summary for context if available
            if (previousSummary != null) {
                """Previous summary: $previousSummary

New notifications to add to the summary:
$basePrompt

Please provide an updated summary that incorporates both the previous summary and new notifications. $lengthInstruction"""
            } else {
                basePrompt
            }
        } else {
            val basePrompt = "Summarise these $name messages $hint. Be direct, no preamble:\n\n$msgs"

            if (previousSummary != null) {
                """Previous summary: $previousSummary

New $name messages to add to the summary:
$msgs

Please provide an updated summary that incorporates both the previous context and new messages. $lengthInstruction Be direct, no preamble."""
            } else {
                basePrompt
            }
        }
        val images = buf.mapNotNull { it.imageBase64 }

        return try {
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
                else -> { log("error", "Unknown provider: $provider"); null }
            }
        } catch (e: Exception) {
            log("error", "AI exception [$provider]: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
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

        log("info", "Ollama OpenAI-compat body: $body")
        log("info", "Ollama OpenAI-compat headers: ${headers.keys}")
        log("info", "Ollama OpenAI-compat body length: ${body.length}")

        return try {
            val conn = openConn(URL(endpoint), headers, readTimeout = 60000)
            conn.outputStream.writer().use { it.write(body) }
            conn.outputStream.flush()
            conn.outputStream.close()
            val code = conn.responseCode
            log("info", "Ollama OpenAI-compat response code: $code")
            if (code == 200) {
                val json = JSONObject(conn.inputStream.reader().readText())
                val result = json.getJSONArray("choices")
                    .getJSONObject(0)
                    .getJSONObject("message")
                    .getString("content").trim()
                log("success", "Ollama OpenAI-compat response OK — ${result.length} chars")
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
        log("warn", "Gemini Nano on-device inference not yet available in this build — requires AICore SDK integration")
        return null
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
                            appIcon: Bitmap? = null, notificationColor: Int? = null) {
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

        // Retain original notification actions (Reply, Mark as read, etc.)
        val retainActions = spBool("retain_original_actions", true)
        log("info", "Actions settings: retain_original_actions=$retainActions, found=${actions.size}")
        if (retainActions && actions.isNotEmpty()) {
            log("info", "Attaching ${actions.size} original action(s) to summary")
            actions.take(5).forEach { action ->
                try {
                    builder.addAction(action)
                    log("info", "  + action: ${action.title}")
                } catch (e: Exception) {
                    log("warn", "  Could not attach action '${action.title}': ${e.javaClass.simpleName}: ${e.message}")
                }
            }
        } else {
            log("info", "No actions attached: retainActions=$retainActions, actionsEmpty=${actions.isEmpty()}")
        }

        // Use unique ID so new summaries don't replace previous ones
        val uniqueId = "${pkg}:summary:${System.currentTimeMillis()}".hashCode()
        nm.notify(uniqueId, builder.build())
        log("success", "Summary notification posted for $name (id=$uniqueId)")
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

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun appName(pkg: String) = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg.split(".").last().replaceFirstChar { it.uppercase() } }
}
