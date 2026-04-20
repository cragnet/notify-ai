# Notify AI

AI-powered notification summariser for Android. Capture notifications from selected apps, batch them, and get AI-generated summaries.

## Features

- **Smart Batching:** Groups notifications from the same app, triggers summary when threshold reached
- **Custom AI Prompts:** Personalise how the AI summarises your notifications
- **Multiple AI Providers:** OpenAI, Google Gemini, Claude, OpenRouter, Gemini Nano (on-device), Ollama (cloud)
- **Original Actions Preserved:** Reply, Mark as read, and other actions carried to summary notification
- **Click to Open:** Tap any summary notification to jump directly to the originating app
- **App Icons & Colors:** Summary notifications show the app's icon and original notification color
- **Per-App Settings:** Choose which apps to monitor and individual thresholds
- **Stats & History:** Track intercepted vs summarised notifications with daily/weekly/monthly charts
- **File Persistence:** Stats written to USB for backup
- **Cloud Builds:** APK built automatically via GitHub Actions on every push

## Supported AI Providers

| Provider | API Key Required | Notes |
|----------|-----------------|-------|
| OpenAI / Compatible | Yes | Use with OpenAI, Ollama Cloud, or any OpenAI-compatible API |
| Google Gemini | Yes | Cloud-based Gemini models |
| Gemini Nano | No | On-device AI (Pixel 8+ or supported devices only) |
| Claude (Anthropic) | Yes | Via OpenRouter or direct |
| OpenRouter | Yes | Access to many models including free tiers |

## Quick Start

1. **Install APK** from releases
2. **Grant permissions:**
   - Notification access
   - App usage access
   - Battery optimisation exclusion
3. **Configure AI Provider:**
   - Open Settings → AI Provider
   - Select provider, enter API key, model name
   - For Ollama Cloud: use OpenAI Compatible with `https://ollama.com/v1`
4. **Select Apps:** Per-app settings → choose apps to monitor
5. **Custom Prompt (optional):** Settings → Custom AI Prompt to personalise summaries

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

### File Persistence
Stats are written to `/data/data/com.craigadams.notifyai/files/stats/YYYY-MM-DD.json` for backup purposes.

## Troubleshooting

**No summaries appearing:**
- Check notification access granted
- Verify AI provider configured (model name, API key, URL)
- Check per-app settings — apps must be selected
- Check threshold setting

**Battery optimisation:** Some manufacturers (Samsung, Xiaomi) reset this on reboot — re-grant permission.

## License

MIT License — feel free to fork and modify.
