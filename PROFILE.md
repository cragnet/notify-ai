# Notify AI — App Profile

Notify AI is an Android notification summarisation app that intercepts notifications from selected apps, batches them, sends them to an AI provider for summarisation, and delivers a new notification containing the summary while retaining the original notification actions such as Reply and Mark as read. It supports Ollama (self-hosted), Google Gemini, and Gemini Nano (on-device). Settings, provider configuration, and app selections can be exported and imported as JSON files. The app maintains a 30-day history of intercepted notifications, a real-time service log, and usage statistics showing interception and summarisation counts by app across daily, weekly, and monthly periods.

## Development Plan

### Phase 1 — Core functionality (current)
The notification interception and buffering is working. History and stats are populating. The immediate priorities are confirming that the AI call to Gemini or Ollama is completing successfully and that the summary notification is being posted with the correct actions attached. The log tab should show this end to end once a threshold is met.

### Phase 2 — Stability
Once summarisation is confirmed working, the focus shifts to reliability. This includes ensuring the service survives device restarts, handling API errors gracefully with retry logic, and preventing notification storms if a selected app sends a burst of notifications. The debounce logic handles bursts but edge cases need testing.

### Phase 3 — Polish
Remaining UI work includes a proper app icon, a notification channel for summaries that allows the user to control sound and vibration independently of the status channel, and a way to view the full text of a summarised notification from the history screen by tapping it.

### Phase 4 — Gemini Nano
Gemini Nano on-device requires integration with Google's AICore SDK which needs to be added as a dependency. This is a separate piece of work as it requires the device to have AICore installed and the model downloaded, and the API is different from a REST call.

### Phase 5 — Optional enhancements
Per-app threshold overrides, custom prompt templates per app, a widget showing recent summary counts, and the option to add custom providers using any OpenAI-compatible endpoint.