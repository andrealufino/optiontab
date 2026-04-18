# Event Routing — Option+Tab Switcher

## Context

OptionTab intercepts `Option+Tab` globally and presents a window-switcher overlay.
The overlay must support:
- Cycling forward with repeated `Tab` while `Option` is held
- Cycling backward with `Shift+Tab`
- Confirming on `Option` release
- Cancelling on `Escape` or click outside

Getting keyboard events to flow correctly requires understanding how macOS routes
events between Carbon hotkeys, NSEvent global monitors, and NSEvent local monitors.

## Decision

**Carbon `RegisterEventHotKey` drives both open and cycle, not NSEvent.**

| Event | Source |
|---|---|
| `Option+Tab` — open overlay (first press) | Carbon hotkey id=1 → `onHotKeyPressed` |
| `Option+Tab` — cycle forward (subsequent presses) | Carbon hotkey id=1 → `show(for:)` → `cycleForward()` |
| `Option+Shift+Tab` — cycle backward | Carbon hotkey id=2 → `onShiftHotKeyPressed` → `cycleBackward()` |
| `Option` release → confirm | NSEvent **local** monitor `.flagsChanged` |
| `Escape` → cancel | NSEvent **local** monitor `.keyDown` |
| Click outside → cancel | NSEvent **local** monitor `.leftMouseDown` / `.rightMouseDown` |
| Global monitor | Safety-net only (panel without key status, e.g. Mission Control) |

## Why Carbon drives cycling (not the local NSEvent monitor)

Carbon `RegisterEventHotKey` **swallows the event from the Cocoa pipeline**. When
`Option+Tab` fires, the system consumes it before generating an `NSEvent.keyDown`.
This means neither the global nor the local NSEvent monitor ever sees a keyDown
for `Option+Tab`. Attempts to cycle via `NSEvent.addLocalMonitorForEvents` on
keyCode 48 + `.option` silently no-op.

Consequence: `Option+Shift+Tab` (backward cycling) also needs its own dedicated
Carbon hotkey registration — the same swallow applies.

## Why `.flagsChanged` is on the local monitor (not global)

`OverlayPanel` has `canBecomeKey = true`. When `makeKeyAndOrderFront` is called,
the panel becomes the key window of our process. At that point:

- `NSEvent.addGlobalMonitorForEvents` only receives events destined for **other**
  apps — it no longer sees our own modifier events.
- `NSEvent.addLocalMonitorForEvents` receives events destined for our process,
  including `.flagsChanged`.

Therefore `.flagsChanged` must be in the local monitor's match mask. The global
monitor retains `.flagsChanged` as a safety-net for rare cases where the panel
fails to acquire key status.

## Why Carbon auto-repeat is not a concern

Carbon `RegisterEventHotKey` fires once per physical press-down. It does not
produce reliable auto-repeat (empirical evidence: Hammerspoon #1179 showed
between 1 and ~33 firings when holding a key). The cycling model is tap-based
— one `Tab` press = one position advance — so single-fire-per-press is exactly
correct.

## Affected files

- `optiontab/Services/HotKeyService.swift` — registers both Carbon hotkeys, routes
  to `onHotKeyPressed` (id=1) and `onShiftHotKeyPressed` (id=2)
- `optiontab/Services/EventMonitorService.swift` — local monitor includes
  `.flagsChanged`; `handleFlagsChanged(_:)` shared between local and global paths
- `optiontab/Overlay/OverlayController.swift` — `show(for:)` calls `cycleForward()`
  when `isVisible`; `cycleBackwardIfVisible()` exposed for the shift hotkey path
- `optiontab/AppDelegate.swift` — wires `onShiftHotKeyPressed` to
  `cycleBackwardIfVisible()`
