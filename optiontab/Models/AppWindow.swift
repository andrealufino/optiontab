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

    /// Stable identifier for use in SwiftUI lists. Derived from the AX element pointer.
    let id: Int

    /// The process identifier of the owning application.
    let pid: pid_t

    /// The underlying Accessibility element for this window.
    let axElement: AXUIElement

    /// The window title. Falls back to `"Untitled"` when the AX attribute is absent.
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
