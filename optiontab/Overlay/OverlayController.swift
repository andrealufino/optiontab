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
/// It coordinates `WindowListService`, `EventMonitorService`, and `WindowRaiser`.
@Observable
@MainActor
final class OverlayController {

    // MARK: Properties

    /// The windows currently displayed in the overlay.
    private(set) var windows: [AppWindow] = []

    /// The index of the currently highlighted row.
    private(set) var selectedIndex: Int = 0

    /// Whether the overlay panel is currently visible.
    private(set) var isVisible: Bool = false

    private var panel: OverlayPanel?
    private let windowListService = WindowListService()
    private let windowRaiser = WindowRaiser()
    let eventMonitor = EventMonitorService()


    // MARK: Initialization

    init() {
        wireEventMonitor()
    }


    // MARK: Public Methods

    /// Shows the overlay for the current frontmost application.
    ///
    /// If the overlay is already visible, cycles the selection forward instead.
    /// Does nothing when the frontmost app has no standard windows.
    ///
    /// - Parameter app: The application whose windows to list.
    func show(for app: NSRunningApplication) async {
        if isVisible {
            cycleForward()
            return
        }

        let fetched = await windowListService.windows(for: app)
        guard !fetched.isEmpty else {
            print("[Overlay] no standard windows — suppressing overlay")
            return
        }

        windows = fetched
        selectedIndex = fetched.count > 1 ? 1 : 0

        presentPanel()
        eventMonitor.start()
        isVisible = true
    }

    /// Dismisses the overlay without raising any window.
    func cancel() {
        guard isVisible else { return }
        print("[Overlay] cancelled")
        dismissPanel()
    }

    /// Raises the currently selected window and dismisses the overlay.
    func confirm() {
        guard isVisible else { return }
        guard selectedIndex < windows.count else {
            dismissPanel()
            return
        }
        let target = windows[selectedIndex]
        print("[Overlay] confirming selection: '\(target.title)'")
        dismissPanel()
        windowRaiser.raise(target)
    }

    /// Raises `window` directly (mouse click on a specific row).
    ///
    /// - Parameter window: The window the user clicked.
    func confirmSelection(_ window: AppWindow) {
        guard isVisible else { return }
        print("[Overlay] direct click on '\(window.title)'")
        dismissPanel()
        windowRaiser.raise(window)
    }

    /// Moves the selection forward by one row, wrapping around.
    func cycleForward() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    /// Moves the selection backward by one row, wrapping around.
    func cycleBackward() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    /// Moves the selection backward only if the overlay is currently visible.
    ///
    /// Used by the global `Option+Shift+Tab` Carbon hotkey, which can fire
    /// independently of the overlay state.
    func cycleBackwardIfVisible() {
        guard isVisible else { return }
        cycleBackward()
    }

    /// Updates the selected index to match a hover event from a row view.
    ///
    /// - Parameter index: The row index the cursor is hovering over.
    func hoverSelected(_ index: Int) {
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
    private func dismissPanel() {
        guard let panel else { return }
        eventMonitor.stop()
        isVisible = false
        windows = []
        selectedIndex = 0

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
        eventMonitor.onOptionReleased = { [weak self] in self?.confirm() }
        eventMonitor.onTabPressed = { [weak self] in self?.cycleForward() }
        eventMonitor.onShiftTabPressed = { [weak self] in self?.cycleBackward() }
        eventMonitor.onDownArrowPressed = { [weak self] in self?.cycleForward() }
        eventMonitor.onUpArrowPressed = { [weak self] in self?.cycleBackward() }
        eventMonitor.onEscapePressed = { [weak self] in self?.cancel() }
        eventMonitor.onClickOutsideOverlay = { [weak self] in self?.cancel() }
    }
}
