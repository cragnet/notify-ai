# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-04-23

### Added

- **Scheduled digest summaries** — configure specific times (e.g. 09:00, 13:00, 18:00) when all buffered notifications are flushed and summarized regardless of threshold count. Uses `AlarmManager` with exact alarms.
- **Light / system theme support** — toggle between Dark, Light, and System-default themes from Settings.
- **Auto-retry & offline queue** — when an AI call fails (network error, timeout, HTTP error), the notification batch is queued and retried automatically with exponential backoff (max 3 attempts).
- **Gemini Nano on-device inference** — integrates `com.google.ai.edge.generativeai` SDK for true on-device summarization via Google Play Services / AICore (Pixel 8+ and supported devices).
- **Navigation restructure** — History is now the primary/default tab. Settings is accessible via the bottom nav or via a cog icon in the AppBar of every other tab.

### Changed

- Bumped version to 2.0.0 (major release).
- Updated `provider_config.dart` to note Gemini Nano requires AICore / Play Services.
- Added Android permissions: `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`.

### Fixed

- Gemini Nano provider no longer returns a stub; it now calls the real on-device model.

## [1.1.0] - Previous release

- Multi-conversation grouping and deduplication for WhatsApp, Telegram, etc.
- Per-app notification color selection
- Custom AI prompt templates with variable substitution (`{app_name}`, `{count}`, `{length}`, etc.)
- File persistence for stats backup
- GitHub Actions CI/CD builds

