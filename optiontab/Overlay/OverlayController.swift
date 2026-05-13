//
//  OverlayController.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation
import SwiftUI


/// Manages the lifecycle, content, and selection state of the window-switcher overlay.
///
/// `OverlayController` is the single source of truth for whether the overlay is
/// visible, which windows are listed, and which row is currently selected.
/// It coordinates `WindowListService`, `EventMonitorService`, `OptionKeyMonitor`,
/// and `WindowRaiser`.
@Observable
@MainActor
final class OverlayController {


    // MARK: Private types

    /// Internal lifecycle state of the overlay.
    ///
    /// Using an explicit state machine prevents the race where `isShowing: Bool`
    /// would be reset by a `defer` while `confirm()` is still awaiting the raise.
    private enum ShowState {
        /// No overlay activity. Accepts a new `show(for:)` call.
        case idle
        /// Window enumeration is in flight. New `show` calls are dropped.
        case loading
        /// Panel is on screen and awaiting user input.
        case visible
        /// Confirm is in progress (raise queued). Guards against double-confirm.
        case confirming
    }

    /// Direction for the initial selection when the overlay becomes visible.
    private enum CycleDirection {
        case forward
        case backward
    }


    // MARK: Properties

    /// The windows currently displayed in the overlay.
    private(set) var windows: [AppWindow] = []

    /// The index of the currently highlighted row.
    private(set) var selectedIndex: Int = 0

    /// Whether the overlay panel is currently visible.
    ///
    /// Computed from the internal state machine so there is a single source of
    /// truth and no risk of the stored bool diverging from `state`.
    var isVisible: Bool { state == .visible }

    /// Whether hover-based selection is enabled for the current overlay session.
    ///
    /// Starts as `false` on each show/cycle so that a stationary cursor under
    /// the panel does not passively override the keyboard-driven selection.
    /// Becomes `true` on the first `.mouseMoved` event delivered to the local monitor.
    private var mouseHoverEnabled: Bool = false

    private var state: ShowState = .idle

    /// Direction the user requested before the overlay became visible.
    ///
    /// Set to `.backward` when `Option+Shift+Tab` fires during loading, so the
    /// initial selection starts at `count - 1` rather than `1`.
    private var pendingDirection: CycleDirection = .forward

    private var panel: OverlayPanel?
    private let windowListService = WindowListService()
    private let windowRaiser = WindowRaiser()
    let eventMonitor = EventMonitorService()
    private let optionKeyMonitor: OptionKeyMonitor

    /// Provides cross-Space window discovery state at overlay show time.
    ///
    /// Wired by `AppDelegate` to `PermissionsService.isScreenRecordingGranted`.
    /// Returns `false` when omitted so the overlay degrades gracefully if it is
    /// ever instantiated without a configured permissions source.
    var isScreenRecordingGranted: () -> Bool = { false }


    // MARK: Initialization

    /// - Parameter optionKeyMonitor: The always-on Option-release tracker injected from `AppDelegate`.
    init(optionKeyMonitor: OptionKeyMonitor) {
        self.optionKeyMonitor = optionKeyMonitor
        wireEventMonitor()
    }


    // MARK: Public Methods

    /// Shows the overlay for the current frontmost application.
    ///
    /// If the overlay is already visible, cycles the selection forward instead.
    /// Does nothing when the frontmost app has no standard windows.
    ///
    /// Handles the rapid-press race: if Option is released while window
    /// enumeration is in flight (before `EventMonitorService` is installed),
    /// `OptionKeyMonitor` captures the release timestamp and this method
    /// auto-confirms the default selection after presenting the panel.
    ///
    /// - Parameter app: The application whose windows to list.
    func show(for app: NSRunningApplication) async {
        if state == .visible {
            cycleForward()
            return
        }
        guard state == .idle else { return }
        state = .loading
        pendingDirection = .forward

        let showStartedAt = Date()

        let fetched = await windowListService.windows(
            for: app,
            includeOtherSpaces: isScreenRecordingGranted()
        )

        // The frontmost app may have changed while enumeration was async.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            print("[Overlay] frontmost app changed during fetch — aborting")
            state = .idle
            return
        }

        guard !fetched.isEmpty else {
            print("[Overlay] no standard windows — suppressing overlay")
            state = .idle
            return
        }

        windows = fetched
        let initialIndex: Int
        switch pendingDirection {
        case .forward:  initialIndex = fetched.count > 1 ? 1 : 0
        case .backward: initialIndex = fetched.count > 1 ? fetched.count - 1 : 0
        }
        selectedIndex = initialIndex
        mouseHoverEnabled = false

        presentPanel()
        eventMonitor.start()
        state = .visible

        // Race resolution: detect an Option release that occurred while enumeration
        // was in flight, before EventMonitorService was installed.
        let releasedDuringLoad = optionKeyMonitor.consumeReleaseAfter(showStartedAt)
        let optionStillDown = OptionKeyMonitor.isOptionCurrentlyDown()

        if releasedDuringLoad && !optionStillDown {
            if fetched.count == 1 {
                // Only window is the frontmost itself — raising would be a no-op
                // with a visible flicker. Dismiss cleanly instead.
                print("[Overlay] Option released during load, single window — dismissing")
                dismissPanelImmediate()
                state = .idle
                return
            }
            print("[Overlay] Option released during load — auto-confirming index \(initialIndex)")
            state = .confirming
            await confirm()
        }
    }

    /// Dismisses the overlay without raising any window.
    func cancel() {
        guard state == .visible else { return }
        print("[Overlay] cancelled")
        state = .idle
        dismissPanel()
    }

    /// Raises the currently selected window and dismisses the overlay.
    ///
    /// `state` is flipped to `.confirming` before `dismissPanelImmediate()` to
    /// prevent a double-confirm — both the global and local `NSEvent` monitors
    /// can deliver `flagsChanged` for the same Option release, and without the
    /// pre-dismiss state flip both Tasks would pass the guard.
    func confirm() async {
        guard state == .visible || state == .confirming else { return }
        guard selectedIndex < windows.count else {
            dismissPanelImmediate()
            state = .idle
            return
        }
        state = .confirming
        let target = windows[selectedIndex]
        print("[Overlay] confirming selection: '\(target.title)'")
        // Tear down the panel synchronously *before* raise so it relinquishes
        // key-window status. Without this the destination window arrives on
        // its Space but stays greyed out — the system still considers our
        // fading overlay panel the key window when raise fires.
        dismissPanelImmediate()
        windowRaiser.raise(target)
        state = .idle
    }

    /// Raises `window` directly (mouse click on a specific row).
    ///
    /// - Parameter window: The window the user clicked.
    func confirmSelection(_ window: AppWindow) async {
        guard state == .visible else { return }
        print("[Overlay] direct click on '\(window.title)'")
        state = .confirming
        dismissPanelImmediate()
        windowRaiser.raise(window)
        state = .idle
    }

    /// Moves the selection forward by one row, wrapping around.
    func cycleForward() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        mouseHoverEnabled = false
    }

    /// Moves the selection backward by one row, wrapping around.
    func cycleBackward() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        mouseHoverEnabled = false
    }

    /// Moves the selection backward, or records the direction for the pending show.
    ///
    /// Used by the global `Option+Shift+Tab` Carbon hotkey, which can fire
    /// independently of the overlay state. If the overlay is loading, stores the
    /// direction so `show(for:)` starts at `count - 1` after enumeration.
    func cycleBackwardIfVisible() {
        switch state {
        case .visible:
            cycleBackward()
        case .loading:
            pendingDirection = .backward
        case .idle, .confirming:
            break
        }
    }

    /// Updates the selected index to match a hover event from a row view.
    ///
    /// Ignored until `mouseHoverEnabled` is true — i.e., until the mouse has
    /// actually moved after the overlay appeared or after the last keyboard cycle.
    ///
    /// - Parameter index: The row index the cursor is hovering over.
    func hoverSelected(_ index: Int) {
        guard mouseHoverEnabled else { return }
        guard index >= 0, index < windows.count else { return }
        selectedIndex = index
    }


    // MARK: Private Methods

    /// Creates and positions the overlay panel, then hosts the SwiftUI content.
    private func presentPanel() {
        let panel = OverlayPanel()
        self.panel = panel
        eventMonitor.overlayPanel = panel

        let view = SwitcherListView(controller: self)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        panel.contentView = hosting
        panel.sizeToFit()
        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)

        print("[Overlay] panel presented")
    }

    /// Fades the panel out and tears down state.
    ///
    /// Used by `cancel()` — does not hand focus to another window, so the
    /// 150 ms animation is safe. `confirm()` uses `dismissPanelImmediate()`
    /// instead to relinquish key-window status before the raise fires.
    private func dismissPanel() {
        guard let panel else { return }
        eventMonitor.stop()
        windows = []
        selectedIndex = 0
        mouseHoverEnabled = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }

        self.panel = nil
        print("[Overlay] panel dismissed")
    }

    /// Tears down the overlay synchronously, without the fade-out animation.
    ///
    /// Used by `confirm()` / `confirmSelection(_:)` to ensure the panel
    /// relinquishes key-window status before `WindowRaiser` runs the SLPS+AX
    /// raise sequence.
    ///
    /// Mirrors AltTab's `hideTilesPanelWithoutChangingKeyWindow()`
    /// (`App.swift:84-87`): flip `canBecomeKey` to `false` *before* orderOut so
    /// macOS does not pick our own panel as the next key window while we are
    /// trying to hand focus to a cross-Space target. Without this dance, the
    /// destination window arrives on its Space but stays greyed out.
    private func dismissPanelImmediate() {
        guard let panel else { return }
        eventMonitor.stop()
        windows = []
        selectedIndex = 0
        mouseHoverEnabled = false

        panel.canBecomeKeyOverride = false
        panel.orderOut(nil)
        panel.canBecomeKeyOverride = true

        self.panel = nil
        #if DEBUG
        print("[Overlay] panel dismissed (immediate, canBecomeKey guard)")
        #endif
    }

    /// Centers the panel on the screen containing `NSEvent.mouseLocation`.
    ///
    /// - Parameter panel: The panel to position.
    private func centerPanel(_ panel: OverlayPanel) {
        let mouseScreen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        panel.setFrameOrigin(NSPoint(
            x: mouseScreen.frame.midX - panel.frame.width / 2,
            y: mouseScreen.frame.midY - panel.frame.height / 2
        ))
    }

    /// Wires `EventMonitorService` callbacks to controller actions.
    private func wireEventMonitor() {
        eventMonitor.onOptionReleased = { [weak self] in
            Task { @MainActor in await self?.confirm() }
        }
        eventMonitor.onTabPressed = { [weak self] in self?.cycleForward() }
        eventMonitor.onShiftTabPressed = { [weak self] in self?.cycleBackward() }
        eventMonitor.onDownArrowPressed = { [weak self] in self?.cycleForward() }
        eventMonitor.onUpArrowPressed = { [weak self] in self?.cycleBackward() }
        eventMonitor.onEscapePressed = { [weak self] in self?.cancel() }
        eventMonitor.onClickOutsideOverlay = { [weak self] in self?.cancel() }
        eventMonitor.onMouseMoved = { [weak self] in self?.mouseHoverEnabled = true }
    }
}
