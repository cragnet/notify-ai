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

    data class Buffered(
        val title: String,
        val text: String,
        val actions: List<Notification.Action>,
        val sbnKey: String,
        val imageBase64: String? = null
    )

    private val buffer = mutableMapOf<String, MutableList<Buffered>>()
    private val debounce = mutableMapOf<String, Runnable>()
    private val DEBOUNCE_MS = 4000L

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
            sp().getString("flutter.$key", null)?.toIntOrNull() ?: def
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
            val result = (0 until arr.length()).map { arr.getString(it) }
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

        // Dump raw pref value so we can verify spList parsing
        val rawApps = sp().getString("flutter.enabled_apps_set", null)
        log("info", "raw enabled_apps_set: ${rawApps?.take(120) ?: "(null)"}")

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
        val pkg = sbn.packageName
        if (pkg == applicationContext.packageName) return

        log("info", "--- Notification from: $pkg ---")

        if (!spBool("service_enabled", true)) { log("info", "Service disabled"); return }

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) { log("warn", "No apps selected"); return }
        if (!selected.contains(pkg)) { log("info", "$pkg not selected — skipping"); return }

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE)
            ?: extras.getString(Notification.EXTRA_CONVERSATION_TITLE)
            ?: run { log("warn", "No title"); return }

        // Extract text: try EXTRA_TEXT, EXTRA_BIG_TEXT, then MessagingStyle messages
        val text: String = run {
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.takeIf { it.length >= 3 }
                ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.takeIf { it.length >= 3 }
                ?: extractMessagingText(extras)
                ?: run { log("warn", "No usable text"); return }
        }

        val name = appName(pkg)
        val image = extractImage(sbn.notification)
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        log("info", "INTERCEPTED from $name: title='$title' text='${text.take(60)}'")
        log("info", "  actions=${actions.size} hasImage=${image != null}")

        saveHistory(pkg, name, title, text, image != null)
        recordStat(pkg, intercepted = true, summarised = false)

        buffer.getOrPut(pkg) { mutableListOf() }
            .add(Buffered(title, text, actions, sbn.key, image))

        val threshold = spInt("notification_threshold", 2)
        val count = buffer[pkg]?.size ?: 0
        log("info", "Buffer $count/$threshold for $name")

        debounce[pkg]?.let { handler.removeCallbacks(it) }

        val runnable = Runnable {
            val buf = buffer[pkg]?.toList() ?: return@Runnable
            val thr = spInt("notification_threshold", 2)
            if (buf.size < thr) { log("info", "Below threshold ${buf.size}/$thr"); return@Runnable }

            buffer.remove(pkg)
            debounce.remove(pkg)
            log("info", "Threshold met — processing ${buf.size} from $name")

            // Dismiss originals and collect their actions
            val allActions = buf.flatMap { it.actions }.distinctBy { it.title?.toString() }
            if (spBool("dismiss_on_app_usage", true)) {
                buf.forEach { try { cancelNotification(it.sbnKey) } catch (_: Exception) {} }
                log("info", "Dismissed ${buf.size} originals from $name, retained ${allActions.size} actions")
            }

            executor.execute {
                val summary = callAI(pkg, buf)
                if (summary != null) {
                    postSummary(pkg, summary, allActions, buf.size)
                    recordStat(pkg, intercepted = false, summarised = true)
                    log("success", "Summary posted for $name: \"${summary.take(100)}\"")
                } else {
                    log("error", "No summary returned for $name — check provider/key/model settings")
                }
            }
        }

        debounce[pkg] = runnable
        handler.postDelayed(runnable, if (threshold == 1) 1500L else DEBOUNCE_MS)
    }

    // ── AI dispatch ────────────────────────────────────────────────────────────

    private fun callAI(pkg: String, buf: List<Buffered>): String? {
        val provider = spStr("ai_provider", "ollama")
        val apiKey  = spStr("api_key_$provider", "")
        val model   = spStr("model_$provider", "")
        val baseUrl = spStr("base_url_$provider", "")
        val length  = spInt("summary_length", 2)

        log("info", "AI call: provider=$provider model=${model.ifEmpty { "(none)" }} url=${baseUrl.ifEmpty { "(default)" }} hasKey=${apiKey.isNotEmpty()} msgs=${buf.size}")

        if (model.isEmpty() && provider != "gemini_nano") {
            log("error", "AI SKIP: no model set for $provider — configure in AI Provider settings"); return null
        }
        if (provider == "ollama" && baseUrl.isEmpty()) {
            log("error", "AI SKIP: no URL set for Ollama — configure in AI Provider settings"); return null
        }
        if (provider == "gemini" && apiKey.isEmpty()) {
            log("error", "AI SKIP: no API key set for Gemini — configure in AI Provider settings"); return null
        }

        val hint = when (length) {
            1 -> "in one very brief sentence"
            3 -> "in 2-3 sentences with key details"
            else -> "in one clear sentence"
        }

        val name = appName(pkg)
        val msgs = buf.joinToString("\n") { "• ${it.title}: ${it.text}" }
        val prompt = "Summarise these $name messages $hint. Be direct, no preamble:\n\n$msgs"
        val images = buf.mapNotNull { it.imageBase64 }

        return try {
            when (provider) {
                "ollama"      -> callOllama(baseUrl, model, prompt, apiKey)
                "gemini"      -> callGemini(apiKey, model, prompt, images)
                "gemini_nano" -> callGeminiNano(prompt)
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
        val endpoint = "${baseUrl.trimEnd('/')}/api/generate"
        log("info", "Ollama POST $endpoint model=$model")

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
            log("success", "Ollama response OK — ${result.length} chars")
            return result
        }
        val errBody = conn.errorStream?.reader()?.readText()?.take(300) ?: "(no body)"
        log("error", "Ollama HTTP $code: $errBody")
        return null
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

    // ── Post summary notification ──────────────────────────────────────────────

    private fun postSummary(pkg: String, summary: String,
                            actions: List<Notification.Action>, count: Int) {
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

        // Retain original notification actions (Reply, Mark as read, etc.)
        if (spBool("retain_original_actions", true)) {
            log("info", "Attaching ${actions.size} original action(s) to summary")
            actions.take(3).forEach { action ->
                try {
                    builder.addAction(action)
                    log("info", "  + action: ${action.title}")
                } catch (e: Exception) {
                    log("warn", "  Could not attach action '${action.title}': ${e.message}")
                }
            }
        }

        nm.notify("$pkg:summary".hashCode(), builder.build())
        log("success", "Summary notification posted for $name")
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
            val msgs = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return null
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
            connectTimeout = 15000
            this.readTimeout = readTimeout
            doOutput = true
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
        } catch (_: Exception) {}
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun appName(pkg: String) = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg.split(".").last().replaceFirstChar { it.uppercase() } }
}
