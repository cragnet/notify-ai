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
    // Flutter SharedPreferences stores keys with "flutter." prefix
    // Booleans/ints stored as native types in flutter_shared_preferences v2+

    private fun sp() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun spBool(key: String, def: Boolean): Boolean {
        val sp = sp()
        // Try native bool first, then string fallback
        return try {
            if (sp.contains("flutter.$key")) sp.getBoolean("flutter.$key", def) else def
        } catch (e: ClassCastException) {
            sp.getString("flutter.$key", null)?.equals("true") ?: def
        }
    }

    private fun spInt(key: String, def: Int): Int {
        val sp = sp()
        return try {
            if (sp.contains("flutter.$key")) sp.getInt("flutter.$key", def) else def
        } catch (e: ClassCastException) {
            sp.getString("flutter.$key", null)?.toIntOrNull() ?: def
        }
    }

    private fun spStr(key: String, def: String): String =
        sp().getString("flutter.$key", def) ?: def

    // Flutter stores StringList as JSON array string
    private fun spList(key: String): List<String> {
        val raw = sp().getString("flutter.$key", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (_: Exception) { emptyList() }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onListenerConnected() {
        super.onListenerConnected()
        log("success", "=== Listener CONNECTED ===")

        // Dump all relevant prefs so we can see what the service is reading
        val sp = sp()
        val allKeys = sp.all.keys.filter { it.startsWith("flutter.") }.sorted()
        log("info", "SharedPrefs has ${allKeys.size} flutter.* keys")
        allKeys.forEach { key ->
            val shortKey = key.removePrefix("flutter.")
            val value = sp.all[key]?.toString()?.take(80) ?: "null"
            log("info", "  $shortKey = $value")
        }

        val selected = spList("enabled_apps_set")
        if (selected.isEmpty()) {
            log("warn", "No apps selected — go to Per-app settings and select apps to monitor")
            postStatusNotification("Notify AI running — action needed",
                "No apps selected. Open app → Per-app settings to choose apps.")
        } else {
            log("success", "Monitoring ${selected.size} app(s): ${selected.joinToString(", ") { it.split(".").last() }}")
            postStatusNotification("Notify AI running",
                "Monitoring ${selected.size} app(s). Waiting for notifications.")
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        log("warn", "=== Listener DISCONNECTED — system killed it ===")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestRebind(android.content.ComponentName(this, NotificationService::class.java))
            log("info", "Requested rebind")
        }
    }

    // ── onNotificationPosted ───────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName

        // Skip our own notifications silently
        if (pkg == applicationContext.packageName) return

        log("info", "--- Notification received from: $pkg ---")

        // Check service enabled
        val enabled = spBool("service_enabled", true)
        log("info", "service_enabled=$enabled")
        if (!enabled) {
            log("info", "Service is disabled — skipping")
            return
        }

        // Check selected apps
        val selected = spList("enabled_apps_set")
        log("info", "enabled_apps_set has ${selected.size} entries: $selected")

        if (selected.isEmpty()) {
            log("warn", "No apps selected — ignoring notification from $pkg")
            return
        }
        if (!selected.contains(pkg)) {
            log("info", "$pkg not in selected list — ignoring")
            return
        }

        // Extract content
        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE)
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

        log("info", "title='$title' text='${text?.take(50)}'")

        if (title == null) { log("warn", "No title — skipping"); return }
        if (text == null || text.length < 3) { log("warn", "No/short text — skipping"); return }

        val name = appName(pkg)
        val image = extractImage(sbn.notification)
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        log("info", "appName=$name, hasImage=${image != null}, actions=${actions.size}")
        log("info", "Buffering notification from $name: \"${title.take(60)}\"")

        saveHistory(pkg, name, title, text, image != null)
        recordStat(pkg, intercepted = true, summarised = false)

        buffer.getOrPut(pkg) { mutableListOf() }
            .add(Buffered(title, text, actions, sbn.key, image))

        val threshold = spInt("notification_threshold", 2)
        val count = buffer[pkg]?.size ?: 0
        log("info", "Buffer for $name: $count/$threshold")

        debounce[pkg]?.let { handler.removeCallbacks(it) }

        val runnable = Runnable {
            val buf = buffer[pkg]?.toList() ?: return@Runnable
            val thr = spInt("notification_threshold", 2)

            log("info", "Debounce fired for $name — buf=${buf.size} threshold=$thr")

            if (buf.size < thr) {
                log("info", "Below threshold — waiting for more from $name")
                return@Runnable
            }

            buffer.remove(pkg)
            debounce.remove(pkg)

            log("info", "Threshold met — processing ${buf.size} notification(s) from $name")

            val dismissOriginals = spBool("dismiss_on_app_usage", true)
            log("info", "dismiss_on_app_usage=$dismissOriginals")
            if (dismissOriginals) {
                buf.forEach { try { cancelNotification(it.sbnKey) } catch (_: Exception) {} }
                log("info", "Dismissed ${buf.size} original(s)")
            }

            executor.execute {
                log("info", "Starting AI call for $name")
                val summary = callAI(pkg, buf)
                if (summary != null) {
                    val allActions = buf.flatMap { it.actions }.distinctBy { it.title?.toString() }
                    postSummary(pkg, summary, allActions, buf.size)
                    recordStat(pkg, intercepted = false, summarised = true)
                    log("success", "Summary posted for $name: \"${summary.take(100)}\"")
                } else {
                    log("error", "AI returned null for $name — check provider/key/model in settings")
                }
            }
        }

        debounce[pkg] = runnable
        handler.postDelayed(runnable, if (threshold == 1) 1500L else DEBOUNCE_MS)
        log("info", "Debounce scheduled — will fire in ${if (threshold == 1) 1500 else DEBOUNCE_MS}ms")
    }

    // ── AI dispatch ────────────────────────────────────────────────────────────

    private fun callAI(pkg: String, buf: List<Buffered>): String? {
        val provider = spStr("ai_provider", "claude")
        val apiKey = spStr("api_key_$provider", "")
        val model = spStr("model_$provider", "")
        val baseUrl = spStr("base_url_$provider", defaultUrl(provider))
        val length = spInt("summary_length", 2)

        log("info", "AI config: provider=$provider model=$model baseUrl=$baseUrl hasKey=${apiKey.isNotEmpty()}")

        if (model.isEmpty()) {
            log("error", "No model configured for $provider — set one in AI Provider settings")
            return null
        }
        if (provider != "ollama" && provider != "local" && provider != "gemini_nano" && apiKey.isEmpty()) {
            log("error", "No API key for $provider — set one in AI Provider settings")
            return null
        }

        val hint = when (length) {
            1 -> "in one very brief sentence (max 10 words)"
            3 -> "in 2-3 sentences with key details"
            else -> "in one clear sentence"
        }

        val name = appName(pkg)
        val msgs = buf.joinToString("\n") { "• ${it.title}: ${it.text}" }
        val prompt = "Summarise these $name messages $hint. Be direct, no preamble:\n\n$msgs"
        val images = buf.mapNotNull { it.imageBase64 }
        val vision = supportsVision(provider, model)

        log("info", "Calling $provider / $model — ${buf.size} message(s)${if (images.isNotEmpty() && vision) " + ${images.size} image(s)" else ""}")

        return try {
            val result = when (provider) {
                "claude"     -> callClaude(apiKey, model, prompt, baseUrl, if (vision) images else emptyList())
                "openai"     -> callOpenAI(apiKey, model, prompt, baseUrl, if (vision) images else emptyList())
                "openrouter" -> callOpenAI(apiKey, model, prompt, "https://openrouter.ai",
                    if (vision) images else emptyList(),
                    extra = mapOf("HTTP-Referer" to "com.craigadams.notifyai"))
                "gemini"     -> callGemini(apiKey, model, prompt, if (vision) images else emptyList())
                "ollama"     -> callOllama(baseUrl, model, prompt, apiKey)
                "local"      -> callOpenAI(apiKey, model, prompt, baseUrl)
                else         -> { log("error", "Unknown provider: $provider"); null }
            }
            log("info", "AI response: ${result?.take(100) ?: "null"}")
            result
        } catch (e: Exception) {
            log("error", "AI exception [$provider]: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    private fun supportsVision(provider: String, model: String) = when (provider) {
        "claude"     -> true
        "openai"     -> model.contains("gpt-4")
        "gemini"     -> true
        "openrouter" -> model.contains("claude") || model.contains("gpt-4o") || model.contains("gemini")
        else         -> false
    }

    // ── API implementations ────────────────────────────────────────────────────

    private fun callClaude(key: String, model: String, prompt: String,
                           base: String, images: List<String>): String? {
        val endpoint = "${base.trimEnd('/')}/v1/messages"
        log("info", "Claude POST $endpoint")
        val url = URL(endpoint)
        val content = JSONArray()
        images.forEach { b64 ->
            content.put(JSONObject().apply {
                put("type", "image")
                put("source", JSONObject().apply {
                    put("type", "base64"); put("media_type", "image/jpeg"); put("data", b64)
                })
            })
        }
        content.put(JSONObject().apply { put("type", "text"); put("text", prompt) })
        val body = JSONObject().apply {
            put("model", model); put("max_tokens", 150)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user"); put("content", content)
            }))
        }.toString()
        val conn = openConn(url, mapOf("x-api-key" to key, "anthropic-version" to "2023-06-01"))
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        log("info", "Claude response code: $code")
        if (code == 200) {
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("content").getJSONObject(0).getString("text").trim()
        }
        val err = conn.errorStream?.reader()?.readText()?.take(300)
        log("error", "Claude error $code: $err")
        return null
    }

    private fun callOpenAI(key: String, model: String, prompt: String, base: String,
                           images: List<String> = emptyList(),
                           extra: Map<String, String> = emptyMap()): String? {
        val endpoint = "${base.trimEnd('/')}/v1/chat/completions"
        log("info", "OpenAI-compat POST $endpoint")
        val url = URL(endpoint)
        val msgContent: Any = if (images.isEmpty()) prompt else {
            JSONArray().apply {
                images.forEach { b64 ->
                    put(JSONObject().apply {
                        put("type", "image_url")
                        put("image_url", JSONObject().apply { put("url", "data:image/jpeg;base64,$b64") })
                    })
                }
                put(JSONObject().apply { put("type", "text"); put("text", prompt) })
            }
        }
        val body = JSONObject().apply {
            put("model", model); put("max_tokens", 150)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user"); put("content", msgContent)
            }))
        }.toString()
        val headers = mutableMapOf<String, String>()
        if (key.isNotEmpty()) headers["Authorization"] = "Bearer $key"
        headers.putAll(extra)
        val conn = openConn(url, headers)
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        log("info", "OpenAI-compat response code: $code")
        if (code == 200) {
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").getString("content").trim()
        }
        val err = conn.errorStream?.reader()?.readText()?.take(300)
        log("error", "OpenAI-compat error $code: $err")
        return null
    }

    private fun callGemini(key: String, model: String, prompt: String,
                           images: List<String>): String? {
        val endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key"
        log("info", "Gemini POST model=$model")
        val url = URL(endpoint)
        val parts = JSONArray()
        images.forEach { b64 ->
            parts.put(JSONObject().apply {
                put("inline_data", JSONObject().apply {
                    put("mime_type", "image/jpeg"); put("data", b64)
                })
            })
        }
        parts.put(JSONObject().apply { put("text", prompt) })
        val body = JSONObject().apply {
            put("contents", JSONArray().put(JSONObject().apply { put("parts", parts) }))
            put("generationConfig", JSONObject().apply { put("maxOutputTokens", 150) })
        }.toString()
        val conn = openConn(url, emptyMap())
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        log("info", "Gemini response code: $code")
        if (code == 200) {
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts")
                .getJSONObject(0).getString("text").trim()
        }
        val err = conn.errorStream?.reader()?.readText()?.take(300)
        log("error", "Gemini error $code: $err")
        return null
    }

    private fun callOllama(base: String, model: String, prompt: String, key: String): String? {
        if (base.isEmpty()) {
            log("error", "Ollama: no base URL set — configure it in AI Provider settings")
            return null
        }
        val endpoint = "${base.trimEnd('/')}/api/generate"
        log("info", "Ollama POST $endpoint model=$model")
        val url = URL(endpoint)
        val body = """{"model":"$model","prompt":"${esc(prompt)}","stream":false}"""
        val headers = if (key.isNotEmpty()) mapOf("Authorization" to "Bearer $key") else emptyMap()
        val conn = openConn(url, headers, readTimeout = 120000)
        conn.outputStream.writer().use { it.write(body) }
        val code = conn.responseCode
        log("info", "Ollama response code: $code")
        if (code == 200) {
            return JSONObject(conn.inputStream.reader().readText()).getString("response").trim()
        }
        val err = conn.errorStream?.reader()?.readText()?.take(300)
        log("error", "Ollama error $code: $err")
        return null
    }

    private fun openConn(url: URL, headers: Map<String, String>,
                         readTimeout: Int = 30000): HttpURLConnection {
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            connectTimeout = 15000
            this.readTimeout = readTimeout
            doOutput = true
        }
    }

    // ── Post summary notification ──────────────────────────────────────────────

    private fun postSummary(pkg: String, summary: String,
                            actions: List<Notification.Action>, count: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val groupId = "notify_ai_group_$pkg"
        val channelId = "notify_ai_$pkg"
        val name = appName(pkg)
        log("info", "Posting summary notification for $name")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannelGroup(NotificationChannelGroup(groupId, name))
            val ch = NotificationChannel(channelId, "$name Summaries",
                NotificationManager.IMPORTANCE_DEFAULT).apply { group = groupId }
            nm.createNotificationChannel(ch)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId)
        else @Suppress("DEPRECATION") Notification.Builder(this)

        val label = if (count > 1) "$count messages · " else ""
        builder.setContentTitle("$name · AI Summary")
            .setContentText(summary)
            .setStyle(Notification.BigTextStyle().bigText(summary)
                .setSummaryText("${label}AI summary"))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setGroup(groupId)

        val retainActions = spBool("retain_original_actions", true)
        log("info", "retain_original_actions=$retainActions, available actions=${actions.size}")
        if (retainActions) {
            actions.take(3).forEach { try { builder.addAction(it) } catch (_: Exception) {} }
        }

        nm.notify("$pkg:summary".hashCode(), builder.build())
        log("success", "Summary notification posted successfully for $name")
    }

    private fun postStatusNotification(title: String, text: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "notify_ai_status"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(channelId, "Notify AI Status",
                    NotificationManager.IMPORTANCE_DEFAULT)
                nm.createNotificationChannel(ch)
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, channelId)
            else @Suppress("DEPRECATION") Notification.Builder(this)
            builder.setContentTitle(title).setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_info).setAutoCancel(true)
            nm.notify("status".hashCode(), builder.build())
        } catch (e: Exception) {
            log("warn", "Status notification failed: ${e.message}")
        }
    }

    // ── Image extraction ───────────────────────────────────────────────────────

    private fun extractImage(n: Notification): String? {
        return try {
            val extras = n.extras
            val pic = extras.getParcelable<Bitmap>(Notification.EXTRA_PICTURE)
            if (pic != null) { log("info", "Found EXTRA_PICTURE in notification"); return toBase64(pic) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val icon = extras.getParcelable<Icon>(Notification.EXTRA_LARGE_ICON)
                if (icon != null) {
                    val d = icon.loadDrawable(this)
                    if (d is BitmapDrawable) { log("info", "Found large icon bitmap"); return toBase64(d.bitmap) }
                }
            }
            null
        } catch (e: Exception) { log("warn", "Image extract failed: ${e.message}"); null }
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
        } catch (e: Exception) { log("warn", "toBase64 failed: ${e.message}"); null }
    }

    // ── Logging — writes with flutter. prefix so Flutter reads it back ─────────

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

    private fun defaultUrl(provider: String) = when (provider) {
        "claude"     -> "https://api.anthropic.com"
        "openai"     -> "https://api.openai.com"
        "openrouter" -> "https://openrouter.ai"
        else         -> ""
    }

    private fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")
        .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}
