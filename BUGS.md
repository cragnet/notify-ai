# Known Issues & Bug Tracker

## Version 2.0.0

### New Known Issues

| Feature | Status | Notes |
|---------|--------|-------|
| Digest alarm permission (Android 12+) | ⚠️ Manual step | `SCHEDULE_EXACT_ALARM` requires user to grant permission in system settings if denied. App redirects automatically. |
| Gemini Nano device support | ⚠️ Limited | Requires AICore delivered via Google Play Services. Only Pixel 8+ and select devices. Falls back gracefully with log warning. |
| Light theme card colours | ⚠️ Minor | Some hard-coded dark-theme colours in `history_screen.dart` and `stats_screen.dart` may appear slightly off in light mode. |
| Retry queue actions | ⚠️ Expected | Original notification action intents (e.g. Reply) are lost on retry after process restart. Action buttons are recreated as placeholders. |

## Fixed Issues

### ClassCastException Crash (RESOLVED)
- **Date:** 2026-04-14
- **Issue:** App crashed with `java.lang.Long cannot be cast to java.lang.String` when processing notifications from certain apps (BuzzKill, WhatsApp, MacroDroid)
- **Root Cause:** `spInt()` function in `NotificationService.kt` had faulty error handling — `getString()` fallback threw second exception
- **Fix:** Wrapped `getString()` fallback in nested try-catch to gracefully return default value
- **Commit:** `d1b1f4a` and subsequent fixes

## Current Status

| Feature | Status | Notes |
|---------|--------|-------|
| BuzzKill notifications | ✅ Working | ClassCastException fix verified |
| WhatsApp notifications | ✅ Working | Threshold and batching functional |
| Custom AI prompts | ✅ Working | Full feature with {length} variables |
| Stats file persistence | ✅ Working | Daily JSON files to app storage |
| OpenAI provider | ✅ Working | Restored to provider list |
| GitHub Actions build | ✅ Working | Cloud builds functional |
| History tab | ✅ Working | Fixed flutter. prefix issue |
| Digest summaries | ✅ Working | AlarmManager-based scheduled flushes |
| Light theme | ✅ Working | ThemeMode toggle with Material 3 |
| Retry queue | ✅ Working | Offline enqueue + network-aware drain |
| Gemini Nano | ✅ Working | Integrated via AI Edge SDK |

## Open Issues

### GitHub Actions Build Fails (IN PROGRESS)
- **Issue:** Builds fail due to OutOfMemoryError on GitHub Actions free tier (7GB RAM limit)
- **Solution:** Making repo public to access 16GB RAM runners
- **Status:** Awaiting repo visibility change

### Feedbin 4hr Summary Script (KNOWN ISSUE)
- **Issue:** Script occasionally fails with edit error
- **Impact:** Feedbin rollups may not generate automatically
- **Workaround:** Run manually or check logs

## Reporting New Issues

If you encounter bugs:
1. Check this file first
2. Note the app version (from About screen)
3. Note Android version and device
4. Check logs: Settings → View Logs (if available)
5. Create GitHub issue with reproduction steps
