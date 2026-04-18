//
//  WindowListService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Enumerates the standard windows of an application using the Accessibility API.
struct WindowListService {

    // MARK: Public Methods

    /// Returns the list of standard windows for `app`, ordered most-focused first.
    ///
    /// Filters out non-standard subroles (palettes, sheets, inspectors) and OptionTab's own windows.
    ///
    /// - Parameter app: The running application to enumerate.
    /// - Returns: An array of `AppWindow` values, or an empty array when AX access fails.
    func windows(for app: NSRunningApplication) async -> [AppWindow] {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        guard let axWindows: [AXUIElement] = attribute(of: appElement, key: kAXWindowsAttribute) else {
            print("[AX] could not read windows for pid \(pid)")
            return []
        }

        // Determine the focused window to mark it
        let focusedWindow: AXUIElement? = attribute(of: appElement, key: kAXFocusedWindowAttribute)

        var result: [AppWindow] = []

        for axWindow in axWindows {
            // Filter by subrole — keep only standard windows
            guard let subrole: String = attribute(of: axWindow, key: kAXSubroleAttribute),
                  subrole == kAXStandardWindowSubrole else {
                continue
            }

            let title: String = attribute(of: axWindow, key: kAXTitleAttribute) ?? "Untitled"
            let isMinimized: Bool = attribute(of: axWindow, key: kAXMinimizedAttribute) ?? false

            // Use the pointer as a stable id
            var ptr: UInt = 0
            withUnsafeBytes(of: axWindow) { ptr = $0.load(as: UInt.self) }
            let windowID = Int(bitPattern: ptr)

            let isFocused: Bool = {
                guard let focused = focusedWindow else { return false }
                return CFEqual(axWindow, focused)
            }()

            result.append(AppWindow(
                id: windowID,
                pid: pid,
                axElement: axWindow,
                title: title.isEmpty ? "Untitled" : title,
                isMinimized: isMinimized,
                isFocused: isFocused
            ))
        }

        // Put focused window first, then preserve AX traversal order
        result.sort { $0.isFocused && !$1.isFocused }

        print("[AX] found \(result.count) standard window(s) for \(app.localizedName ?? "?")")
        return result
    }


    // MARK: Private Helpers

    /// Type-safe wrapper around `AXUIElementCopyAttributeValue`.
    ///
    /// - Parameters:
    ///   - element: The AX element to query.
    ///   - key: The AX attribute key constant.
    /// - Returns: The attribute value cast to `T`, or `nil` on failure.
    private func attribute<T>(of element: AXUIElement, key: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
              let result = value as? T else {
            return nil
        }
        return result
    }
}
