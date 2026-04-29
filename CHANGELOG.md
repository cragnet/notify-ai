# Changelog

All notable changes to this project will be documented in this file.

## [2.0.8] - 2026-04-29

### Added

- **Summary cooldown** — prevents rapid-fire summaries when threshold is set to 1. After a summary is posted for an app, new summaries for the same app are deferred for a configurable cooldown period (default 30s, adjustable 0–120s in Settings). Notifications that arrive during the cooldown accumulate in the buffer and are batched into a single summary when the cooldown expires. This fixes the issue where WhatsApp (and similar apps) produced multiple AI summaries within seconds for the same conversation.

## [2.0.7] - 2026-04-28

### Added

- **Per-app notification thresholds** — override the global "Summarise after" threshold for individual apps directly in Per-app settings. Defaults to the global value unless customised. Ideal for WhatsApp and other messaging apps that group multiple messages into a single notification.

## [2.0.6] - 2026-04-23

### Fixed

- **WhatsApp placeholder text in summaries** — notifications with text like "2 new messages" were being sent to the AI as actual content. These are now filtered out before buffering.
- **Notification buffer losing content during WhatsApp stacking** — `onNotificationRemoved` was removing old notifications before the runnable could summarize them. Now removals are skipped while a summary runnable is pending, letting the runnable capture all content before clearing.
- **Stale summary notifications not dismissed** — when the user taps "Mark as read" on an original notification and the app/system dismisses it, the summary notification is now automatically cancelled if no buffered notifications remain.
- **Debounce leak on threshold deferral** — the runnable wasn't removing itself from the debounce map when deferring due to insufficient notifications, causing `onNotificationRemoved` to skip cleanups indefinitely.

## [2.0.5] - 2026-04-23

### Fixed

- **Stale test notifications polluting summaries** — test notifications injected via "Send test notification" were accumulating in the buffer. If they didn't reach threshold, they stayed indefinitely and later combined with real notifications, producing summaries with old test content. Now stale test notifications are cleared before each new test injection.
- **Notification dismissal race condition with WhatsApp** — when WhatsApp stacks messages, it updates the notification key. The old key dismissal had no effect, leaving the original notification visible. Added a 600ms fallback that scans active notifications for the package and cancels any remaining ones after summary posting.

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

