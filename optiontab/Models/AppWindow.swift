//
//  AppWindow.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import CoreGraphics
import Foundation


/// Represents a single application window discovered via Accessibility, Core Graphics, or both.
///
/// Two distinct discovery sources contribute entries:
/// - **Accessibility** (`AXUIElementCreateApplication` + `kAXWindowsAttribute`) sees only
///   windows on the active Space, but provides a usable `AXUIElement` for raising and
///   deminimizing.
/// - **Core Graphics** (`CGWindowListCopyWindowInfo`) sees windows across all Spaces but
///   yields no AX handle. Windows discovered only via CG carry a `nil` `axElement` and
///   are raised through a re-resolution pass after the owning app is activated (see
///   `WindowRaiser`).
struct AppWindow: Identifiable, Equatable {

    // MARK: Properties

    /// Stable identifier for use in SwiftUI lists.
    ///
    /// When a `CGWindowID` is available (either from the AX SPI or because the entry
    /// originates from Core Graphics) it is used directly. AX-only entries fall back
    /// to the AX element pointer address — this can never collide with a real
    /// `CGWindowID` in practice because pointer addresses on 64-bit systems sit far
    /// outside the 32-bit `CGWindowID` range.
    let id: Int

    /// The process identifier of the owning application.
    let pid: pid_t

    /// The underlying Accessibility element for this window, or `nil` for CG-only entries.
    let axElement: AXUIElement?

    /// The window server identifier, populated when known.
    ///
    /// Used for AX↔CG dedup and to re-resolve a fresh `AXUIElement` after a Space
    /// switch when the entry is CG-only.
    let cgWindowID: CGWindowID?

    /// The window title. Falls back to `"Untitled"` when no title is available.
    let title: String

    /// Whether the window is currently minimized to the Dock.
    ///
    /// Always `false` for CG-only entries: minimized windows are reported by AX
    /// (when on the active Space) and Core Graphics filters them out via the
    /// alpha/bounds checks.
    let isMinimized: Bool

    /// Whether this window is the currently focused window of its app.
    ///
    /// Always `false` for CG-only entries — focus is an AX concept and CG-only
    /// entries by definition live on a different Space than the active one.
    let isFocused: Bool


    // MARK: Equatable

    /// Two `AppWindow` values are equal when they share the same identifier.
    static func == (lhs: AppWindow, rhs: AppWindow) -> Bool {
        lhs.id == rhs.id
    }
}
