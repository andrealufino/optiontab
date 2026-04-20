//
//  EventMonitorService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Manages `NSEvent` global and local monitors used while the overlay is visible.
///
/// Global monitors capture events system-wide (needed because our panel is non-activating).
/// Local monitors capture events inside our own panel window.
@MainActor
final class EventMonitorService {

    // MARK: Callbacks

    /// Fired when the `Option` modifier flag is released while overlay is visible.
    var onOptionReleased: (() -> Void)?

    /// Fired when `Tab` is pressed (Option still held).
    var onTabPressed: (() -> Void)?

    /// Fired when `Shift+Tab` is pressed (Option still held).
    var onShiftTabPressed: (() -> Void)?

    /// Fired when `↓` is pressed.
    var onDownArrowPressed: (() -> Void)?

    /// Fired when `↑` is pressed.
    var onUpArrowPressed: (() -> Void)?

    /// Fired when `Escape` is pressed.
    var onEscapePressed: (() -> Void)?

    /// Fired when a click occurs outside the overlay panel. The panel is passed as context.
    var onClickOutsideOverlay: (() -> Void)?

    /// Fired when the mouse moves inside the overlay panel.
    ///
    /// Used to enable hover-based selection only after a real mouse movement,
    /// preventing passive selection when the overlay appears under a stationary cursor.
    var onMouseMoved: (() -> Void)?

    // MARK: Private Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// The overlay panel reference used to detect clicks outside it.
    weak var overlayPanel: NSPanel?


    // MARK: Initialization

    deinit {
        // Best-effort cleanup; monitors hold no strong self reference after stop().
    }


    // MARK: Public Methods

    /// Installs global and local event monitors for overlay interaction.
    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleLocalEvent(event)
            }
            return event
        }

        print("[Overlay] event monitors started")
    }

    /// Removes all active event monitors.
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        print("[Overlay] event monitors stopped")
    }


    // MARK: Private Methods

    /// Handles global `flagsChanged` (modifier key state) and `keyDown` events.
    ///
    /// This is the safety-net path: fires when the panel is not key (e.g. Mission
    /// Control is active). The primary path is the local monitor.
    ///
    /// - Parameter event: The `NSEvent` received from the global monitor.
    private func handleGlobalEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    /// Handles local events (keyboard + mouse) while the panel is key.
    ///
    /// - Parameter event: The `NSEvent` received from the local monitor.
    private func handleLocalEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        case .leftMouseDown, .rightMouseDown:
            handleMouseDown(event)
        case .mouseMoved:
            onMouseMoved?()
        default:
            break
        }
    }

    /// Fires `onOptionReleased` when the Option modifier transitions to off.
    ///
    /// - Parameter event: A `flagsChanged` `NSEvent`.
    private func handleFlagsChanged(_ event: NSEvent) {
        if !event.modifierFlags.contains(.option) {
            print("[Overlay] Option released — confirming")
            onOptionReleased?()
        }
    }

    /// Routes key events to the appropriate callback.
    ///
    /// - Parameter event: A `keyDown` `NSEvent`.
    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags
        let isOptionHeld = flags.contains(.option)

        switch event.keyCode {
        case 48: // Tab
            if isOptionHeld {
                if flags.contains(.shift) {
                    onShiftTabPressed?()
                } else {
                    onTabPressed?()
                }
            }
        case 125: // Down arrow
            onDownArrowPressed?()
        case 126: // Up arrow
            onUpArrowPressed?()
        case 53: // Escape
            print("[Overlay] Escape pressed — cancelling")
            onEscapePressed?()
        default:
            break
        }
    }

    /// Dismisses the overlay when a mouse click lands outside the panel bounds.
    ///
    /// - Parameter event: A mouse-down `NSEvent`.
    private func handleMouseDown(_ event: NSEvent) {
        guard let panel = overlayPanel else {
            onClickOutsideOverlay?()
            return
        }

        let clickLocation = NSEvent.mouseLocation
        let panelFrame = panel.frame

        if !panelFrame.contains(clickLocation) {
            print("[Overlay] click outside overlay — cancelling")
            onClickOutsideOverlay?()
        }
    }
}
