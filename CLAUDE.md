# CLAUDE.md — OptionTab

## Project overview

**OptionTab** is a native macOS 26+ utility. Pressing `Option+Tab` shows a vertical list of all windows belonging to the currently frontmost application, letting the user switch between them without leaving the keyboard.

- Bundle ID: `com.andrealufino.optiontab`
- Minimum deployment: macOS 26
- Activation policy: `.accessory` (menu bar only, no Dock icon)
- No sandbox, hardened runtime enabled
- Version: 0.1.0

## Tech stack

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- SwiftUI + AppKit hybrid (`NSPanel` hosting `NSHostingView`)
- Carbon `RegisterEventHotKey` for global hotkey (`Option+Tab`)
- `AXUIElement` APIs for window enumeration and raising
- Liquid Glass via `.glassEffect(in:)` (macOS 26+)
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
    ├── WindowListService    ← AXUIElement enumeration, filters standard windows
    ├── EventMonitorService  ← NSEvent global/local monitors (key, flags, mouse)
    ├── WindowRaiser         ← AXRaise + app.activate(), deminimize if needed
    ├── OverlayPanel         ← NSPanel subclass (.nonactivatingPanel, .floating)
    └── SwitcherListView     ← SwiftUI root view, Liquid Glass container
        └── WindowRowView    ← Per-row layout (icon, title, minimized badge)
```

All services are `@Observable @MainActor final class`. Dependency injection via `@Environment` — no singletons.

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
- `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`
- Filter: `kAXStandardWindowSubrole` only
- Focus match: `CFEqual` against `kAXFocusedWindowAttribute` (pointer addresses of `AXUIElement` are not stable across attribute reads)
- Sort: focused window first, then preserve AX traversal order
- Stable ID: pointer address of `AXUIElementRef` (used only within a single enumeration pass)

### Liquid Glass
- One container, one `.glassEffect(in: RoundedRectangle(cornerRadius: 22))`
- No `GlassEffectContainer` needed (single surface, no sibling morphing)
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

## Entitlements

- `com.apple.security.app-sandbox = false` (required for AX and Carbon hotkey)
- `com.apple.security.automation.apple-events = true`
