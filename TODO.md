# Notify AI — Task Tracker

## Active Development

### Recently Completed (v2.0.1)
- [x] Enhanced digest scheduling (fixed times, interval, daily, weekly)
- [x] Per-app digest filtering (all / include-only / exclude)
- [x] Separate digest AI prompt with dedicated default
- [x] Digest settings screen
- [x] Build fix — removed bad Gemini Nano dependency

### Previously Completed (v2.0.0)
- [x] Scheduled digest summaries (AlarmManager-based)
- [x] Light / system theme toggle
- [x] Auto-retry & offline queueing for failed AI calls
- [x] Navigation restructure — History as primary tab, cog icon for Settings
- [x] CHANGELOG.md created
- [x] Documentation updated (README, BUGS, TODO)

### Previously Completed (v1.1.0)
- [x] ClassCastException fix for notification processing
- [x] Custom AI prompt feature with import/export
- [x] Stats file persistence to local storage
- [x] OpenAI provider restored to settings
- [x] "Summarised" label wrapping fix
- [x] Documentation (README, BUGS, TODO)

## Backlog

### Features
- [ ] Add more AI provider options (Groq, etc.)
- [ ] Notification filtering by keyword
- [ ] Custom notification sounds per app
- [ ] Export/import full app settings
- [ ] Widget showing recent summary counts
- [ ] Per-app custom prompt templates
- [ ] Per-app threshold overrides

### Performance
- [ ] Reduce APK size further
- [ ] Optimize memory usage during AI calls
- [ ] Background service battery usage review

### Infrastructure
- [ ] Automated testing for notification handling
- [ ] CI/CD build for multiple Android versions
- [ ] Automated Play Store deployment (future)

## Daily Tasks (Recurring)

- [ ] Monitor backup logs at 10:00 AM
- [ ] Check Ollama model updates
- [ ] Review Feedbin script status

## Contributing

Want to contribute? Check BUGS.md for open issues or suggest features from the backlog.
