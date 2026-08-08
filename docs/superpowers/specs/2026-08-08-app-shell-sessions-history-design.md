# App Shell, Sessions & History — Design Spec

Date: 2026-08-08

## Overview

Evolves Insight from a tray-only utility with a one-shot explanation popup
into a normal Dock app with a tabbed main window (Home / History /
Settings), a light/dark theme toggle, and a popup that supports follow-up
questions and regeneration as part of a resumable, saved session.

A "session" — the original selected text plus the explanation and any
follow-up exchanges — is the core new concept. It is both what the popup
shows live and what gets saved to History, viewed identically in both
places.

This spec builds on `docs/superpowers/specs/2026-08-05-select-explain-design.md`
and supersedes its "Response history/logging" and "Retry/regenerate button
or other rich popup actions" non-goals.

## Non-goals (still out of scope)

- Linux or mobile support.
- Offline/local model fallback.
- Sharing/exporting history entries.
- Multiple simultaneous popups.
- Cloud sync of history across devices/machines.
- Recording which source application a selection came from.
- A "stop generating" control for in-flight streams.

## App shell & presence

- **Dock icon**: remove `LSUIElement` from `macos/Runner/Info.plist` so the
  app gets a normal Dock icon and appears in Cmd+Tab, in addition to the
  existing tray icon.
- **Startup**: the main window still starts hidden — launching the app
  (including via "Launch at login") does not pop a window. It opens via
  the Dock icon, the tray icon, or programmatically (e.g. "Open Settings"
  from a popup error).
- **Closing the window** (native close button) hides it rather than
  quitting, preserving the existing "keeps running in the background"
  behavior and current tab/scroll state.
- **Quit** (tray menu or Cmd+Q) must actually terminate the process. This
  requires a fix alongside this work: `AppDelegate.swift`'s
  `applicationShouldTerminateAfterLastWindowClosed` returning `false` (a
  fix from the original implementation, needed to stop the app dying when
  the main window hides) means window-close no longer doubles as quit.
  `TrayService`'s `onQuit` and the app's Quit path must call a real
  process-termination path (e.g. `dart:io`'s `exit(0)`) instead of
  `windowManager.close()`.
- **Navigation**: top tabs — Home, History, Settings — replacing the bare
  `SettingsScreen` as the main window's content.
- **Tray icon** stays exactly as today (Settings/Quit menu, hotkey-conflict
  warning) as a secondary quick-access surface alongside the Dock icon.
  - Tray's "Settings…" menu item opens the main window directly to the
    Settings tab.
  - The Dock icon (and window re-show generally) opens to whichever tab
    was last viewed, defaulting to Home on first-ever launch.

## Theming

- `AppSettings` gains a `themeMode` field (`light` | `dark`), persisted via
  the existing `shared_preferences`-backed path in `SettingsRepository`
  (not a secret, no secure storage needed). Default: `dark`, matching the
  current popup's look.
- A toggle in the Settings tab switches between light and dark. The change
  applies immediately, without restart, to both the main window and any
  popup opened afterward (an already-open popup does not need to
  live-update).
- Both `MaterialApp` instances (main window, popup window) build their
  `theme`/`darkTheme`/`themeMode` from this setting rather than the
  popup's current hardcoded `Colors.black87` card.

## Sessions & History

### Data model

```dart
class ExplanationSession {
  final String id;
  final String selectedText;
  final DateTime createdAt;
  final List<SessionTurn> turns;
}

enum TurnRole { user, assistant }

class SessionTurn {
  final TurnRole role;
  final String content;
  final DateTime timestamp;
}
```

Turn 0 is always the assistant's initial explanation, generated from the
existing prompt template + `selectedText` (unchanged from today's
behavior). A follow-up question appends a `user` turn, then an
`assistant` turn holding the streamed reply. Regenerate discards and
replaces only the current last `assistant` turn — it does not touch
earlier turns or create a new session.

### Storage

`HistoryRepository` persists the session list as a single JSON file under
the app's support directory (via `path_provider`), matching the project's
existing simple-file style rather than introducing a SQL dependency at
this scale. Interface:

```dart
class HistoryRepository {
  Future<List<ExplanationSession>> loadAll();  // sorted by lastActivityAt desc, prunes >30 days old
  Future<void> save(ExplanationSession session);  // upsert by id
  Future<void> delete(String id);
}
```

`ExplanationSession.lastActivityAt` is a derived getter — the timestamp of
its last turn (falls back to `createdAt` if somehow empty). Sorting and
"newest first" everywhere (Home's recent list, the History list) use this,
not `createdAt`, so resuming an old session and adding a follow-up bumps
it back to the top rather than leaving it stranded at its original
position.

- **Retention**: sessions whose `lastActivityAt` is older than 30 days are
  pruned on `loadAll()`. There is no user-facing cap on count within that
  window.
- **Search**: client-side substring filtering over `selectedText` and all
  turns' `content` — no query engine needed at this scale.
- **Persistence timing**: the popup calls `save()` after every turn
  completes (initial explanation, each follow-up, each regenerate), not
  only on close, so a session survives even if the popup is killed
  mid-conversation.
- **Corrupt/unreadable file**: treated as empty history (log and continue)
  rather than crashing the app — this is convenience data, not critical
  state.

## Popup becomes a session

- Replaces the current fixed 360×200 static card with a resizable
  window (user-draggable edges, minimum 360×400), defaulting to 420×520:
  a header showing the original selected-text context, a scrollable list
  of turns, and a follow-up text input.
- **Header actions**: regenerate (re-runs the last assistant turn),
  copy (copies the last assistant response to the clipboard, reusing
  `ClipboardAccess`), and close (✕).
- **Dismissal**: click-outside/window-blur no longer closes the popup
  (this supersedes the original spec's "closes on window blur"). Only Esc
  or the ✕ button close it. The `_PopupBlurListener` is removed; the
  existing `Focus`/Esc handling in `PopupScreen` stays.
- **Follow-up**: submitting the input field appends a `user` turn and
  sends the full conversation so far to Workers AI, streaming the new
  `assistant` turn in place.
- **Regenerate**: removes the current last `assistant` turn, resends the
  same conversation (without it) to Workers AI, and streams a replacement.
- `WorkersAiClient` changes from a single-prompt `streamExplanation` call
  to a conversation-aware call accepting the full turn history as
  `messages`, since Workers AI's `/ai/run` endpoint already takes a
  `messages` array.
- The message-list + input + action-buttons UI is a single reusable
  widget, `ConversationView`, used both inside the floating popup window
  and inside History's detail view — resuming a saved session looks and
  behaves identically to a live one.

## History tab

- A search box plus a list of sessions (newest first, within the 30-day
  window), each row showing a preview of `selectedText` and a relative
  timestamp.
- Tapping a row opens a detail view embedding `ConversationView` with that
  session's full transcript. Because it's resumable, submitting a
  follow-up or regenerating here works exactly as in the live popup and
  updates the same saved session (via `HistoryRepository.save`).
- Each row (or the detail view) offers a delete action, removing that
  session via `HistoryRepository.delete`.

## Home tab

- A short "recent activity" list — the most recent ~5 sessions (from
  `HistoryRepository.loadAll()`), each tappable to jump to that session in
  the History tab's detail view.
- A reminder of the current shortcut binding (from `AppSettings`) and a
  hotkey-status indicator (registered vs. conflict), reflecting the same
  `HotkeyService.registrationFailed` signal that already drives the
  tray's conflict warning.

## Error handling

| Condition | Behavior |
|---|---|
| Follow-up request fails (network, auth, etc.) | Same inline error treatment as today's initial-explanation errors — shown in place of the pending turn; earlier turns are untouched and still visible. |
| Regenerate request fails | The prior last-assistant-turn is kept as-is (not cleared before the new response arrives) and an inline error is shown alongside it; the user can retry regenerate or leave the original response standing. |
| History file missing/corrupt on load | Treated as empty history; logged, not surfaced as an error to the user. |
| Deleting a session that's also the "resumed" one currently open in a popup | Not handled specially — last write (save or delete) wins. Acceptable given single-user, single-popup-at-a-time usage. |

## Testing

- **Unit tests**: `HistoryRepository` (save/load/prune-by-age/delete,
  corrupt-file fallback), the extended `WorkersAiClient` multi-turn
  streaming call, and the session-turn logic in the popup/session
  controller (append follow-up, regenerate replaces only the last
  assistant turn).
- **Widget tests**: `ConversationView` (rendering turns, submitting a
  follow-up, regenerate, copy), `HomeScreen` (recent list, shortcut/status
  display), `HistoryScreen` (search/filter, delete, opening the detail
  view), and the Settings theme toggle.
- **Manual verification**: Dock icon presence and Cmd+Tab behavior, window
  hide-on-close vs. real quit, popup resizing, and theme switching taking
  effect without restart — OS-level behavior outside `flutter test`'s
  reach, following the same pattern as Task 9 of the original
  implementation plan.
