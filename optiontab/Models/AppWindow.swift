//
//  AppWindow.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Represents a single application window enumerated via the Accessibility API.
struct AppWindow: Identifiable, Equatable {

    // MARK: Properties

    /// Stable identifier for use in SwiftUI lists. Derived from the CGWindowID when available,
    /// otherwise from the AX element pointer.
    let id: Int

    /// The process identifier of the owning application.
    let pid: pid_t

    /// The underlying Accessibility element for this window.
    ///
    /// May be `nil` for windows that live on a different Space and are therefore not
    /// exposed by `kAXWindowsAttribute` at enumeration time. Such windows are still
    /// listed using `CGWindowListCopyWindowInfo` and raised on a best-effort basis.
    let axElement: AXUIElement?

    /// The Core Graphics window identifier, when known.
    ///
    /// Always populated for windows discovered via `CGWindowListCopyWindowInfo`.
    let cgWindowID: CGWindowID?

    /// The window title. Falls back to `"Untitled"` when no title can be read.
    let title: String

    /// Whether the window is currently minimized to the Dock.
    let isMinimized: Bool

    /// Whether this window is the currently focused (frontmost) window of its app.
    let isFocused: Bool


    // MARK: Equatable

    /// Two `AppWindow` values are equal when they wrap the same AX element pointer.
    static func == (lhs: AppWindow, rhs: AppWindow) -> Bool {
        lhs.id == rhs.id
    }
}
