# Notify AI

AI-powered notification summariser for Android. Capture notifications from selected apps, batch them, and get AI-generated summaries.

## Features

- **Smart Batching:** Groups notifications from the same app, triggers summary when threshold reached
- **Summary Cooldown:** Prevents rapid-fire summaries when threshold is set to 1. Buffers burst notifications and summarises them together after a configurable cooldown (default 30s)
- **Scheduled Digest Summaries:** Flush and summarise at fixed times, recurring intervals, daily, or weekly schedules — regardless of threshold
- **Per-App Digest Filtering:** Include all, only selected, or exclude specific apps from digest summaries
- **Separate Digest Prompt:** Custom AI prompt specifically optimised for periodic, multi-app rollups
- **Auto-Retry & Offline Queue:** Failed AI calls are automatically retried with exponential backoff when connectivity returns
- **In-App Service Restart:** Restart the notification listener directly from the app when it stalls or after force-stop
- **Custom AI Prompts:** Personalise how the AI summarises your notifications
- **Multiple AI Providers:** OpenAI, Google Gemini, Claude, OpenRouter, Gemini Nano (on-device via ML Kit), Ollama (self-hosted)
- **Automatic Fallback:** Configure primary, secondary, and tertiary AI providers — if one fails, the next is tried automatically
- **WiFi-Based Provider Switching:** Automatically switch AI provider based on the WiFi network you're connected to — perfect for using a local Ollama server at home
- **Original Actions Preserved:** Reply, Mark as read, and other actions carried to summary notification
- **Click to Open:** Tap any summary notification to jump directly to the originating app
- **App Icons & Colors:** Summary notifications show the app's icon and original notification color
- **Per-App Settings:** Choose which apps to monitor, set custom notification thresholds per app, and pick individual notification colours
- **Stats & History:** Track intercepted vs summarised notifications with daily/weekly/monthly charts
- **Theme Support:** Dark, Light, or System-default theme
- **File Persistence:** Stats written to local storage for backup
- **Cloud Builds:** APK built automatically via GitHub Actions on every push
- **Auto-Incrementing Builds:** CI automatically bumps the build number on every release
- **Buffer Memory Safety:** Hard limits prevent unbounded memory growth (50/app, 200 global, 24h TTL)

## Supported AI Providers

| Provider | API Key Required | Notes |
|----------|-----------------|-------|
| OpenAI / Compatible | Yes | Use with OpenAI, Ollama Cloud, or any OpenAI-compatible API |
| Google Gemini | Yes | Cloud-based Gemini models |
| Gemini Nano | No | On-device AI (Pixel 8+ or supported devices only) |
| Claude (Anthropic) | Yes | Via OpenRouter or direct |
| OpenRouter | Yes | Access to many models including free tiers |
| Local / Custom | Optional | Any OpenAI-compatible local endpoint |

### Backup Providers
Set up to three tiers of AI providers (primary, secondary, tertiary). If the primary fails or is misconfigured, the app automatically tries the secondary, then the tertiary. Each backup uses its own saved model, URL and API key configuration.

## Quick Start

1. **Install APK** from releases
2. **Grant permissions:**
   - Notification access
   - App usage access
   - Battery optimisation exclusion
3. **Configure AI Provider:**
   - Open Settings → AI Provider
   - Select primary provider, enter API key, model name
   - Optionally set Backup provider 1 and Backup provider 2 for automatic fallback
   - Optionally set WiFi-based providers to automatically switch when connected to specific networks (e.g., use local Ollama at home)
   - For Ollama Cloud: use OpenAI Compatible with `https://ollama.com/v1`
4. **Select Apps:** Per-app settings → choose apps to monitor
5. **Set Thresholds (optional):** In Per-app settings, tap the filter icon next to any selected app to set a custom threshold. Useful for chat apps like WhatsApp that group messages into a single notification — set threshold to 1 so every message is summarised immediately
6. **Set Cooldown (optional):** Settings → Summary cooldown controls how long to wait before re-summarising the same app. When threshold=1, a cooldown of 30s prevents WhatsApp and similar apps from producing multiple summaries in seconds for the same conversation. Increase to 60–120s if you still see duplicates
7. **Custom Prompt (optional):** Settings → Custom AI Prompt to personalise summaries

## Building

### Cloud Build (Recommended)
APKs are built automatically via **GitHub Actions** on every push to `main`:
1. Go to [Actions tab](https://github.com/cragnet/notify-ai/actions)
2. Download the `notify-ai-release` artifact from the latest run

### Local Build
**Requirements:**
- Flutter SDK
- Android SDK (API 26+)
- Java 17
- x86_64 architecture (ARM builds not supported due to NDK limitations)

```bash
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Configuration

### Custom AI Prompt
Go to Settings → Custom AI Prompt. Variables available:
- `{app_name}` — Name of the app (e.g., "WhatsApp")
- `{notifications}` — List of notifications as bullet points
- `{count}` — Number of notifications
- `{length}` — Summary length setting (1=brief, 2=balanced, 3=detailed)
- `{length_instruction}` — Full length instruction for the AI
- `{hint}` — Concise hint (e.g., "in one very brief sentence")

### WiFi-Based Provider Switching
Go to Settings → AI Provider → WiFi-based provider 1 / 2. Configure:
- **WiFi SSID:** Exact network name (case-sensitive)
- **Provider to use:** The AI provider that will be used when connected to this network

When connected to a matching WiFi, that provider becomes the effective primary — the normal primary and backups are still used as fallbacks if the WiFi provider fails. This is ideal for using a local Ollama server at home while using cloud providers elsewhere.

**Note:** On Android 10+, reading the WiFi SSID requires location permission. If the SSID cannot be read, the app falls back to the normal primary provider.

### File Persistence
Stats are written to `/data/data/com.craigcarroll.notifyai/files/stats/YYYY-MM-DD.json` for backup purposes.

## Recent Fixes

- **Log spam eliminated:** Notifications from unselected apps no longer clutter logs
- **Cross-conversation actions:** Action retention only happens when all buffered notifications belong to the same conversation
- **Source dismissal race fixed:** Immediate dismissal sweep after summary posting closes the window where new notifications slip through
- **WhatsApp buffer stall fixed:** Updates now correctly schedule a new runnable when the previous one expired
- **Stale summary cancellation:** Summary is auto-cancelled when every original notification that produced it is dismissed
- **Dynamic commit hash:** About screen shows the actual build commit instead of a hardcoded value
- **Retry queue no longer blocks:** Retry processing moved to a background thread so slow AI calls cannot stall new notifications
- **In-app service restart:** Home screen now has a "Restart notification listener" button to recover from force-stop without system settings

## Troubleshooting

**No summaries appearing:**
- Check notification access granted
- Verify AI provider configured (model name, API key, URL)
- Check per-app settings — apps must be selected
- Check threshold setting
- If using backup providers, verify at least one tier is fully configured and reachable

**Source notifications still visible after summary:**
- Ensure "Dismiss original notifications" is enabled in Settings
- Some apps (e.g. Teams, WhatsApp) aggressively re-post — this is app behaviour, not a bug

**WiFi provider not switching:**
- On Android 10+, grant location permission so the app can read the WiFi SSID
- Ensure the SSID is entered exactly (case-sensitive, no extra spaces)
- Some networks broadcast a hidden SSID — WiFi switching may not work on these

**Service stalled / no new summaries after force-stop:**
- Tap **Restart notification listener** on the home screen — this rebinds the service without visiting system settings
- If that fails, clear app data and re-enable notification access in system settings
- Honor/Xiaomi/Samsung devices are especially aggressive about killing background services

**Battery optimisation:** Some manufacturers (Samsung, Xiaomi) reset this on reboot — re-grant permission.

## License

MIT License — feel free to fork and modify.
