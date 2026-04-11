# Notify AI

AI-powered notification summariser for Android.
Supports Claude, OpenAI, Ollama (local/Pi), OpenRouter, Google Gemini, and Gemini Nano (on-device).

---

## Features
- Intercepts notifications from selected apps
- Batches them per-app and sends to AI for summarising
- Posts summary notification retaining original actions (Reply, Mark as read etc.)
- Configurable threshold — summarise after 1, 2…10 notifications
- Per-app grouping — each app gets its own notification channel
- Stats screen — intercepted vs summarised, daily/weekly/monthly chart + per-app breakdown
- Battery optimisation bypass to keep running in background
- Fully responsive — phone, tablet, foldable

---

## Building on Raspberry Pi 5

### Step 1 — Install dependencies
```bash
sudo apt-get update
sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa default-jdk adb
```

### Step 2 — Install Flutter SDK
```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter --version
```

### Step 3 — Install Android SDK
```bash
mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-11076708_latest.zip
mv cmdline-tools latest

echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools' >> ~/.bashrc
source ~/.bashrc

sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

### Step 4 — Configure Flutter
```bash
flutter config --android-sdk ~/android-sdk
flutter doctor --android-licenses
flutter doctor
```

### Step 5 — Enable Wireless Debugging on your phone
1. Settings → About Phone → tap **Build Number** 7 times
2. Settings → **Developer Options** → enable **Wireless Debugging**
3. Tap Wireless Debugging → note the **IP:port**
4. Tap **Pair device with pairing code** → note the pairing port and code

### Step 6 — Connect wirelessly from Pi
```bash
# One-time pairing
adb pair <IP>:<PAIRING_PORT>
# Enter the 6-digit code when prompted

# Connect
adb connect <IP>:<PORT>

# Verify
adb devices
```

### Step 7 — Copy project and build
```bash
# Copy the notify_ai folder to your Pi home directory, then:
cd ~/notify_ai
flutter pub get
flutter run --release

# Or build a standalone APK:
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## First run on phone

1. Open **Notify AI**
2. Tap **AI API key** → choose provider, enter key (or pick Ollama/Gemini Nano for no key)
3. Tap **Notification access** → grant in system settings, return to app
4. Tap **App usage access** → grant, return
5. Tap **Disable battery optimisation** → tap Allow, return
6. Tap the **arrow** to proceed to main app
7. Go to **Per-app settings** → select apps to monitor
8. Set your **threshold slider** and **summary length**
9. Done — notifications will be summarised automatically

---

## AI Providers

| Provider | Key needed | Notes |
|---|---|---|
| Claude (Anthropic) | Yes | console.anthropic.com — Haiku is cheapest |
| OpenAI | Yes | platform.openai.com/api-keys |
| OpenRouter | Yes | openrouter.ai/keys — many free models |
| Google Gemini | Yes | aistudio.google.com/app/apikey |
| Gemini Nano | No | On-device, Pixel 8+ / supported devices only |
| Ollama | No | Runs on your Pi — free, private |

### Ollama on Pi — allow external connections
```bash
sudo systemctl edit ollama
# Add:
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"

sudo systemctl restart ollama
```
Use your Pi's **Tailscale IP** as the Base URL so it works away from home too.
Default URL in app: `http://10.0.1.33:11434`

---

## Troubleshooting

**No summaries appearing**
- Check notification access: Settings → Apps → Special app access → Notification access
- Check threshold — if set to 5 you need 5 notifications from same app first
- Check API key in AI Provider settings

**Battery optimisation keeps turning back on**
- Some manufacturers (Samsung, Xiaomi) reset this — re-grant after each reboot
- Consider also enabling "Auto-start" in your phone's battery/permissions settings

**Ollama not responding**
- Check Ollama is running: `systemctl status ollama`
- Check OLLAMA_HOST is set to 0.0.0.0 (not 127.0.0.1)
- Try opening `http://<PI_IP>:11434` in your phone's browser

**flutter doctor shows issues**
- Run `flutter doctor -v` for detail
- Most common fix: `flutter doctor --android-licenses`
