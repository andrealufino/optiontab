# AGENTS.md — OptionTab

## Project overview

**OptionTab** is a native macOS 14+ utility. Pressing `Option+Tab` shows a vertical list of all windows belonging to the currently frontmost application, letting the user switch between them without leaving the keyboard.

- Bundle ID: `com.andrealufino.optiontab`
- Minimum deployment: macOS 14 (Sonoma)
- Activation policy: `.accessory` (menu bar only, no Dock icon)
- No sandbox, hardened runtime enabled
- Version: 0.1.0

## Tech stack

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- SwiftUI + AppKit hybrid (`NSPanel` hosting `NSHostingView`)
- Carbon `RegisterEventHotKey` for global hotkey (`Option+Tab`)
- `AXUIElement` APIs for window enumeration and raising
- Translucent background via `.ultraThinMaterial` (macOS 14 baseline; Liquid Glass would require macOS 26)
- `SMAppService.mainApp` for Launch at Login
- Zero third-party dependencies

## Architecture

```
AppDelegate              ← NSApplicationDelegateAdaptor, wires all services
├── PermissionsService   ← Polls AXIsProcessTrusted(), drives onboarding
├── HotKeyService        ← Carbon RegisterEventHotKey, fires callback on Option+Tab
├── MenuBarController    ← NSStatusItem + NSMenu
├── LaunchAtLoginService ← SMAppService wrapper
└── OverlayController    ← @Observable, owns overlay lifecycle
    ├── WindowListService    ← AX enumeration (standard + brute-force cross-Space) + CG-only fallback
    ├── EventMonitorService  ← NSEvent global/local monitors (key, flags, mouse)
    ├── WindowRaiser         ← SLPS + make-key-event + kAXRaiseAction (AltTab pattern, off-main queue)
    ├── OverlayPanel         ← NSPanel subclass (.nonactivatingPanel, .floating) with canBecomeKeyOverride
    └── SwitcherListView     ← SwiftUI root view, Liquid Glass container
        └── WindowRowView    ← Per-row layout (icon, title, minimized badge)
```

All services are `@Observable @MainActor final class`. Dependency injection via `@Environment` — no singletons.

Cross-Space window discovery and raising use SkyLight private SPI declared in `AXPrivate.swift` (`_AXUIElementCreateWithRemoteToken`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `CGSCopySpacesForWindows`, `CGSGetWindowLevel`). Touch `CGS_CONNECTION = CGSMainConnectionID()` once at app launch — without it, SLPS calls silently no-op.

## Key patterns

### Hotkey (Carbon)
```swift
// HotKeyService uses nonisolated(unsafe) for Carbon opaque refs in deinit
nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
```

Two hotkeys are registered: `Option+Tab` (forward) and `Option+Shift+Tab` (backward).
Carbon swallows the keyDown event, so NSEvent monitors never see `Option+Tab` —
**all cycling is driven by Carbon, not by NSEvent keyDown**.
Full routing rationale: `docs/260418-01-event-routing-v1.md`.

### Overlay lifecycle
1. `HotKeyService` fires `onHotKeyPressed` / `onShiftHotKeyPressed`
2. `AppDelegate` reads `NSWorkspace.shared.frontmostApplication`, skips self
3. `OverlayController.show(for:)` fetches windows, presents panel, starts event monitor; if already visible, calls `cycleForward()` instead
4. `Option` key release → `confirm()` → raise selected window, dismiss panel
5. `Escape` / click outside → `cancel()` → dismiss without raising

### Window enumeration
- `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute` covers the active Space only on macOS 14+
- Cross-Space: brute-force `_AXUIElementCreateWithRemoteToken` over 1000 axId with magic `0x636F_636F`, filtered by subrole `kAXStandardWindowSubrole` / `kAXDialogSubrole` (AltTab/DockDoor pattern)
- AX entries with `_AXUIElementGetWindow` cgID resolution are filtered against `realCGWindowIDs` (CG layer-0 set) and `isAtLeastNormalLevel` to drop Finder tab pages and palettes
- Dedup by `cgWindowID`; pointer-address fallback only when cgID resolution fails
- Brute-force cache 500 ms TTL per pid (`BruteForceCache`)
- Focus match: `CFEqual` against `kAXFocusedWindowAttribute` (pointer addresses of `AXUIElement` are not stable across attribute reads)
- CG-only fallback (`CGWindowSnapshotProvider`) for windows AX cannot reach; ghost-filter drops `!isOnscreen && isOnActiveSpace && !appIsHidden`

### Cross-Space raise (AltTab pattern)
`WindowRaiser.performHybridRaise` runs on `raiseQueue` background `.userInteractive`:

1. `_GetProcessForPID(pid, &psn)`
2. `_SLPSSetFrontProcessWithOptions(&psn, cgID, SLPSMode.userGenerated.rawValue)` triggers the Space-switch animation
3. `postMakeKeyWindowEvents` posts the 0xf8-byte mouse-down/mouse-up payload
4. `AXUIElementPerformAction(element, kAXRaiseAction)`

Nothing else. **Do not** add `kAXMainWindowAttribute = true`, `kAXFocusedAttribute = true`, `app.activate()` (pre or post), or a retry loop — each of those reintroduces a previously fixed regression (snap-back to previous app, greyed-out destination chrome).

The destination window only ends up promoted to key if the overlay panel relinquishes `canBecomeKey` during its dismiss — see below.

### Overlay dismiss must flip `canBecomeKey`
When `confirm()` / `confirmSelection(_:)` hands focus to a raised window, `dismissPanelImmediate()` runs synchronously:

```swift
panel.canBecomeKeyOverride = false
panel.orderOut(nil)
panel.canBecomeKeyOverride = true
```

`OverlayPanel.canBecomeKeyOverride: Bool` is mutable and read by the `canBecomeKey` override. Without this flip, macOS picks our own panel as the next key window during `orderOut`, leaving the destination cross-Space window raised but greyed out. Mirrors AltTab `App.hideTilesPanelWithoutChangingKeyWindow()`.

The animated dismiss (`dismissPanel()`) is retained for `cancel()` only (Escape, click outside) — those paths do not hand focus elsewhere, so the fade-out is safe.

### Overlay material
- macOS 26+: `.glassEffect(in: RoundedRectangle(cornerRadius: 22))` (Liquid Glass)
- macOS 14–25: `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))` + 1pt white stroke overlay
- Branched via `if #available(macOS 26, *)` in `SwitcherListView.body`; shared scroll content lives in `scrollList` computed property
- `NSPanel.hasShadow = false` — shadow is owned by the SwiftUI shape, not the window system
- `NSPanel.isOpaque = false`, `backgroundColor = .clear`

## Build

Uses XcodeBuildMCP. Config at `.xcodebuildmcp/config.yaml`:

```yaml
schemaVersion: 1
enabledWorkflows:
  - macos
workflows:
  macos:
    projectPath: optiontab.xcodeproj
    scheme: optiontab
```

Build command: `mcp__XcodeBuildMCP__build_macos` (no args needed when config is present).

Always build after code changes. Never assume it compiles.

## Conventions

- Language: English in all code, comments, print statements, and commit messages
- No ViewModel antipattern — use `@Observable` + domain state
- No Combine — `async/await` exclusively
- `struct` by default; `class` only for `@Observable` services
- Every method documented with `///` (description + parameters/returns/throws where applicable)
- `// MARK:` (no separator) for internal grouping; `// MARK: -` for major type/extension boundaries
- File header: standard AML header with `Created by Andrea Mario Lufino`

## Branch strategy

- `main` — stable releases only, never commit directly
- `develop` — all work happens here
- Atomic commits per logical change
- Commit messages: imperative mood, English, no AI attribution
- Git tags use plain semver `X.Y.Z` — never prefix with `v`. Applies to local tags, remote tags, and GitHub Release tag names.

## Entitlements

- `com.apple.security.app-sandbox = false` (required for AX and Carbon hotkey)
- `com.apple.security.automation.apple-events = true`
