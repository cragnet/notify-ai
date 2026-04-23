# Changelog

All notable changes to this project will be documented in this file.

## [2.0.4] - 2026-04-23

### Fixed

- **Missing first message in WhatsApp summaries** — when WhatsApp updates the same notification key with stacked messages, the service was replacing the old notification instead of keeping it. Now both the old and new message content are preserved in the buffer, so all messages appear in the AI summary.

## [2.0.3] - 2026-04-23

### Fixed

- **Gemini Nano coroutine build failure** — replaced `Tasks.await()` with `runBlocking` for ML Kit `checkStatus()` and `generateContent()` calls. ML Kit GenAI Prompt API uses Kotlin `suspend` functions, not the Play Services Tasks API.
- Updated `isGeminiNanoAvailable()` in `MainActivity.kt` to use `runBlocking` with proper coroutine API.

## [2.0.2] - 2026-04-23

### Fixed

- **Gemini Nano build failure** — replaced the non-existent `com.google.ai.edge.generativeai` artifact with the official `com.google.mlkit:genai-prompt:1.0.0-beta2` SDK. Gemini Nano now works via ML Kit GenAI Prompt API with on-device inference, automatic model download, and no API key required.
- Updated `isGeminiNanoAvailable()` to use ML Kit `checkStatus()` instead of checking for the AICore package.

## [2.0.1] - 2026-04-23

### Added

- **Enhanced digest scheduling** — four schedule modes:
  - **Fixed times** — specific clock times (e.g. 09:00, 13:00, 18:00)
  - **Interval** — recurring every N minutes (15 min to 12 hr)
  - **Daily** — once per day at a chosen time
  - **Weekly** — once per week on a chosen day and time
- **Per-app digest filtering** — include all monitored apps, include only selected apps, or exclude specific apps from digests.
- **Separate digest AI prompt** — custom prompt template specifically for periodic digest summaries, with its own default optimised for multi-app, time-accumulated rollups.

### Fixed

- **Build failure** — removed non-existent `com.google.ai.edge.generativeai:generativeai:0.1.0` dependency. Gemini Nano temporarily reverted to placeholder stub.

## [2.0.0] - 2026-04-23

### Added

- **Scheduled digest summaries** — configure specific times when all buffered notifications are flushed and summarized regardless of threshold count. Uses `AlarmManager` with exact alarms.
- **Light / system theme support** — toggle between Dark, Light, and System-default themes from Settings.
- **Auto-retry & offline queue** — when an AI call fails (network error, timeout, HTTP error), the notification batch is queued and retried automatically with exponential backoff (max 3 attempts).
- **Navigation restructure** — History is now the primary/default tab. Settings is accessible via the bottom nav or via a cog icon in the AppBar of every other tab.

### Changed

- Bumped version to 2.0.0 (major release).
- Added Android permissions: `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`.

### Fixed

- Gemini Nano provider stub improved with better error messaging.

## [1.1.0] - Previous release

- Multi-conversation grouping and deduplication for WhatsApp, Telegram, etc.
- Per-app notification color selection
- Custom AI prompt templates with variable substitution (`{app_name}`, `{count}`, `{length}`, etc.)
- File persistence for stats backup
- GitHub Actions CI/CD builds

