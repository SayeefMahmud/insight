# Select & Explain — Design Spec

Date: 2026-08-05

## Overview

A Flutter desktop app (macOS + Windows) that runs in the background from system
startup. The user selects text in any application, presses a global keyboard
shortcut, and a small popup appears near the cursor showing an AI-generated
explanation of the selected text, streamed from Cloudflare Workers AI. Modeled
loosely on macOS's built-in "Look Up" popup.

## Non-goals (out of scope for v1)

- Linux or mobile support.
- Response history/logging.
- Retry/regenerate button or other rich popup actions (copy button, etc.).
- Multiple simultaneous popups.
- Offline/local model fallback.
- Automatic clipboard-conflict resolution beyond simple save/restore.

## Architecture

Single Flutter application process. Two logical windows:

1. **Main window** — hidden by default, no dock/taskbar entry. Hosts app
   logic (hotkey listener, tray icon, settings screen when opened from the
   tray menu).
2. **Popup window** — spawned on demand via `desktop_multi_window`, frameless,
   always-on-top, positioned near the current mouse cursor. Destroyed when
   dismissed.

### Key packages

| Concern | Package |
|---|---|
| Tray icon + menu | `tray_manager` |
| Global hotkey | `hotkey_manager` |
| Simulate copy keypress | `keypress_simulator` |
| Clipboard read/write | `super_clipboard` (or `clipboard`) |
| Cursor screen position | `screen_retriever` |
| Popup window | `desktop_multi_window` |
| Secure token storage | `flutter_secure_storage` |
| Non-secret settings | `shared_preferences` |
| Launch at login | `launch_at_startup` |
| HTTP + SSE streaming | `http` or `dio`, manual SSE chunk parsing |

## Data flow

1. App launches at login. Main window stays hidden; tray icon is shown; the
   configured global hotkey is registered.
2. User selects text in any app and presses the hotkey.
3. Hotkey callback:
   a. Save current clipboard contents.
   b. Simulate Cmd+C (macOS) / Ctrl+C (Windows) via `keypress_simulator`.
   c. Wait ~100ms, then read the clipboard.
   d. Restore the original clipboard contents.
4. Read current cursor screen position via `screen_retriever`.
5. Open a new popup window anchored near that position (frameless,
   always-on-top, no window chrome).
6. Popup shows a loading spinner, then calls the Cloudflare Workers AI REST
   endpoint (`.../ai/run/{model}`) with `stream: true`, substituting the
   captured text into the user's system prompt template (`{{selection}}`
   placeholder).
7. Response tokens stream in and are appended to the popup's text area as
   they arrive.
8. Popup closes on click-outside (window blur) or Esc key.

## Settings

Opened via the tray menu ("Settings…"), shown in the (otherwise hidden) main
window. Fields:

- **Cloudflare Account ID** (plain text, `shared_preferences`)
- **API Token** (secret, `flutter_secure_storage` — OS Keychain on macOS,
  Credential Manager/DPAPI on Windows)
- **Model** — dropdown of common Workers AI text models, plus a free-text
  override field
- **System prompt template** — must contain a `{{selection}}` placeholder;
  validated on save
- **Global shortcut** — hotkey recorder widget; default `Cmd+Shift+E` /
  `Ctrl+Shift+E`
- **Launch at login** — toggle, backed by `launch_at_startup`

All settings are read fresh from storage each time the hotkey fires, so
changes take effect without restarting the app.

## Error handling

| Condition | Behavior |
|---|---|
| Clipboard unchanged after copy simulation (nothing was selected) | Popup shows "No text selected", no API call made |
| Missing/invalid API token or account ID | Popup shows a short error message with a link/button to open Settings |
| Network failure, bad token, rate limit, timeout | Popup shows the error message inline; no automatic retry in v1 |
| Hotkey registration fails (conflict with another app) | Tray notification; user can rebind in Settings |
| macOS Accessibility permission not granted | Detected on startup/first hotkey use; app prompts the user to enable it in System Settings before key simulation/hotkeys will work |

## Platform-specific notes

- **macOS**: both global hotkey registration and keypress simulation require
  Accessibility permission. The app must detect if it's missing and guide the
  user to grant it. Distribution requires code signing and notarization for
  Gatekeeper.
- **Windows**: `SendInput`-based key simulation needs no special permission.
  Code signing is recommended for distribution but not required to run
  locally.

## Testing

- **Unit tests**: clipboard-copy service (mocking key simulation + clipboard
  read/write), Workers AI client's SSE stream parser, settings persistence
  (secure storage + shared preferences round-trip, including the
  `{{selection}}` placeholder validation).
- **Widget tests**: Settings screen validation (required fields, placeholder
  check, shortcut recorder).
- **Manual verification**: hotkey capture, clipboard save/restore, and popup
  positioning tested against a handful of real apps (browser, text editor,
  PDF viewer) on both macOS and Windows — this class of OS-level interaction
  can't be meaningfully automated.
