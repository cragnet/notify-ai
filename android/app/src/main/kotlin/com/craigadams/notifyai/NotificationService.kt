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

    // ── SharedPreferences helpers ──────────────────────────────────────────────
    // Flutter's SharedPreferences plugin stores all keys with a "flutter." prefix.
    // Booleans, ints are stored as their native types by flutter_shared_preferences v2+.
    // StringLists are stored as a JSON array string with key "flutter.<key>".

    private fun sp() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun spBool(key: String, def: Boolean) =
        sp().getBoolean("flutter.$key", def)

    private fun spInt(key: String, def: Int) =
        sp().getInt("flutter.$key", def)

    private fun spStr(key: String, def: String) =
        sp().getString("flutter.$key", def) ?: def

    // Flutter stores StringList as JSON array
    private fun spList(key: String): List<String> {
        val raw = sp().getString("flutter.$key", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (_: Exception) { emptyList() }
    }

    // Write log/history WITHOUT flutter. prefix so Flutter prefs (which adds flutter.)
    // reads them back correctly via getString('service_log') -> reads 'flutter.service_log'
    private fun writeStr(key: String, value: String) {
        sp().edit().putString("flutter.$key", value).apply()
    }

    // ── Main entry point ───────────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!spBool("service_enabled", true)) return

        val pkg = sbn.packageName
        if (pkg == applicationContext.packageName) return

        // Check selected apps
        val selected = spList("enabled_apps_set")
        if (selected.isNotEmpty() && !selected.contains(pkg)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: return
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
        if (text.length < 3) return

        val name = appName(pkg)
        val image = extractImage(sbn.notification)
        val actions = sbn.notification.actions?.toList() ?: emptyList()

        log("info", "Intercepted from $name: \"${title.take(60)}\"${if (image != null) " [+image]" else ""}")
        saveHistory(pkg, name, title, text, image != null)
        recordStat(pkg, intercepted = true, summarised = false)

        buffer.getOrPut(pkg) { mutableListOf() }
            .add(Buffered(title, text, actions, sbn.key, image))

        val threshold = spInt("notification_threshold", 2)
        val count = buffer[pkg]?.size ?: 0
        log("info", "Buffered $count/$threshold from $name")

        debounce[pkg]?.let { handler.removeCallbacks(it) }

        val runnable = Runnable {
            val buf = buffer[pkg]?.toList() ?: return@Runnable
            val thr = spInt("notification_threshold", 2)
            if (buf.size < thr) {
                log("info", "Still waiting — ${buf.size}/$thr from $name")
                return@Runnable
            }

            buffer.remove(pkg)
            debounce.remove(pkg)

            log("info", "Threshold met — summarising ${buf.size} from $name")

            if (spBool("dismiss_on_app_usage", true)) {
                buf.forEach { try { cancelNotification(it.sbnKey) } catch (_: Exception) {} }
                log("info", "Dismissed ${buf.size} original(s) from $name")
            }

            executor.execute {
                val summary = callAI(pkg, buf)
                if (summary != null) {
                    val allActions = buf.flatMap { it.actions }.distinctBy { it.title?.toString() }
                    postSummary(pkg, summary, allActions, buf.size)
                    recordStat(pkg, intercepted = false, summarised = true)
                    log("success", "Summary posted for $name: \"${summary.take(80)}${if (summary.length > 80) "…" else ""}\"")
                } else {
                    log("error", "No summary for $name — check AI Provider config and API key in the app")
                }
            }
        }

        debounce[pkg] = runnable
        handler.postDelayed(runnable, if (threshold == 1) 1500L else DEBOUNCE_MS)
    }

    // ── AI dispatch ────────────────────────────────────────────────────────────

    private fun callAI(pkg: String, buf: List<Buffered>): String? {
        val provider = spStr("ai_provider", "claude")
        val apiKey = spStr("api_key_$provider", "")
        val model = spStr("model_$provider", "")
        val baseUrl = spStr("base_url_$provider", defaultUrl(provider))
        val length = spInt("summary_length", 2)

        if (model.isEmpty()) {
            log("warn", "No model set for $provider — enter one in AI Provider settings")
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

        log("info", "Calling $provider / $model${if (images.isNotEmpty() && vision) " [+${images.size} image(s)]" else ""}")

        return try {
            when (provider) {
                "claude"      -> callClaude(apiKey, model, prompt, baseUrl, if (vision) images else emptyList())
                "openai"      -> callOpenAI(apiKey, model, prompt, baseUrl, if (vision) images else emptyList())
                "openrouter"  -> callOpenAI(apiKey, model, prompt, "https://openrouter.ai",
                    if (vision) images else emptyList(),
                    extra = mapOf("HTTP-Referer" to "com.craigadams.notifyai"))
                "gemini"      -> callGemini(apiKey, model, prompt, if (vision) images else emptyList())
                "ollama"      -> callOllama(baseUrl, model, prompt, apiKey)
                "local"       -> callOpenAI(apiKey, model, prompt, baseUrl)
                "gemini_nano" -> { log("warn", "Gemini Nano on-device not yet implemented"); null }
                else          -> null
            }
        } catch (e: Exception) {
            log("error", "AI call failed [$provider]: ${e.message}")
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
        if (key.isEmpty()) { log("error", "Claude: no API key set"); return null }
        val url = URL("${base.trimEnd('/')}/v1/messages")
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
        val conn = connect(url, mapOf(
            "x-api-key" to key, "anthropic-version" to "2023-06-01"))
        conn.outputStream.writer().use { it.write(body) }
        if (conn.responseCode == 200)
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("content").getJSONObject(0).getString("text").trim()
        log("error", "Claude ${conn.responseCode}: ${conn.errorStream?.reader()?.readText()?.take(200)}")
        return null
    }

    private fun callOpenAI(key: String, model: String, prompt: String, base: String,
                           images: List<String> = emptyList(),
                           extra: Map<String, String> = emptyMap()): String? {
        val url = URL("${base.trimEnd('/')}/v1/chat/completions")
        val msgContent: Any = if (images.isEmpty()) {
            prompt
        } else {
            JSONArray().apply {
                images.forEach { b64 ->
                    put(JSONObject().apply {
                        put("type", "image_url")
                        put("image_url", JSONObject().apply {
                            put("url", "data:image/jpeg;base64,$b64")
                        })
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
        val conn = connect(url, headers)
        conn.outputStream.writer().use { it.write(body) }
        if (conn.responseCode == 200)
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("choices").getJSONObject(0)
                .getJSONObject("message").getString("content").trim()
        log("error", "OpenAI-compat ${conn.responseCode}: ${conn.errorStream?.reader()?.readText()?.take(200)}")
        return null
    }

    private fun callGemini(key: String, model: String, prompt: String,
                           images: List<String>): String? {
        if (key.isEmpty()) { log("error", "Gemini: no API key set"); return null }
        val url = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key")
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
        val conn = connect(url, emptyMap())
        conn.outputStream.writer().use { it.write(body) }
        if (conn.responseCode == 200)
            return JSONObject(conn.inputStream.reader().readText())
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts")
                .getJSONObject(0).getString("text").trim()
        log("error", "Gemini ${conn.responseCode}: ${conn.errorStream?.reader()?.readText()?.take(200)}")
        return null
    }

    private fun callOllama(base: String, model: String, prompt: String, key: String): String? {
        if (base.isEmpty()) { log("error", "Ollama: no URL configured — set Base URL in AI Provider settings"); return null }
        val url = URL("${base.trimEnd('/')}/api/generate")
        val body = """{"model":"$model","prompt":"${esc(prompt)}","stream":false}"""
        val headers = if (key.isNotEmpty()) mapOf("Authorization" to "Bearer $key") else emptyMap()
        val conn = connect(url, headers, timeout = 120000)
        conn.outputStream.writer().use { it.write(body) }
        if (conn.responseCode == 200)
            return JSONObject(conn.inputStream.reader().readText()).getString("response").trim()
        log("error", "Ollama ${conn.responseCode}: ${conn.errorStream?.reader()?.readText()?.take(200)}")
        return null
    }

    private fun connect(url: URL, headers: Map<String, String>,
                        timeout: Int = 30000): HttpURLConnection {
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            connectTimeout = 15000
            readTimeout = timeout
            doOutput = true
        }
    }

    // ── Notification posting ───────────────────────────────────────────────────

    private fun postSummary(pkg: String, summary: String,
                             actions: List<Notification.Action>, count: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val groupId = "notify_ai_group_$pkg"
        val channelId = "notify_ai_$pkg"
        val name = appName(pkg)

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

        if (spBool("retain_original_actions", true)) {
            actions.take(3).forEach { try { builder.addAction(it) } catch (_: Exception) {} }
        }

        nm.notify("$pkg:summary".hashCode(), builder.build())
    }

    // ── Image extraction ───────────────────────────────────────────────────────

    private fun extractImage(n: Notification): String? {
        return try {
            val extras = n.extras
            val pic = extras.getParcelable<android.graphics.Bitmap>(Notification.EXTRA_PICTURE)
            if (pic != null) return toBas64(pic)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val icon = extras.getParcelable<Icon>(Notification.EXTRA_LARGE_ICON)
                if (icon != null) {
                    val d = icon.loadDrawable(this)
                    if (d is BitmapDrawable) return toBas64(d.bitmap)
                }
            }
            null
        } catch (_: Exception) { null }
    }

    private fun toBas64(bmp: Bitmap): String? {
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

    // ── Logging ────────────────────────────────────────────────────────────────
    // Write with flutter. prefix so Flutter prefs reads it back correctly

    private fun log(level: String, msg: String) {
        Log.d(TAG, "[$level] $msg")
        try {
            val sp = sp()
            val key = "flutter.service_log"
            val arr = try { JSONArray(sp.getString(key, "[]")) } catch (_: Exception) { JSONArray() }
            val ts = SimpleDateFormat("HH:mm:ss dd/MM", Locale.getDefault()).format(Date())
            arr.put(JSONObject().apply { put("timestamp", ts); put("level", level); put("message", msg) })
            // Keep last 500
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
            // Prune > 30 days
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
        } catch (_: Exception) {}
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
