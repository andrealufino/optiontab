//
//  WindowListService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import ApplicationServices
import Foundation


/// Private Accessibility SPI: returns the `CGWindowID` backing an `AXUIElement` window.
///
/// This is the same SPI used by AltTab, Rectangle, and many other window managers
/// to bridge the Accessibility and Core Graphics window namespaces. Without it,
/// AX windows and `CGWindowListCopyWindowInfo` entries cannot be reliably matched.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError


/// Enumerates the standard windows of an application across all Spaces.
///
/// Combines two data sources:
/// - `AXUIElementCopyAttributeValue(_, kAXWindowsAttribute, _)` returns only windows on
///   the **current Space**, but provides the AX element required to raise them.
/// - `CGWindowListCopyWindowInfo([.optionAll], …)` returns windows across **all Spaces**,
///   including fullscreen windows that live in their own Space, but yields no AX element.
///
/// Merging both sources via the private `_AXUIElementGetWindow` SPI lets the switcher list
/// every window of an app even when some are fullscreen on other desktops.
struct WindowListService {

    // MARK: Public Methods

    /// Returns the list of standard windows for `app`, ordered most-focused first.
    ///
    /// Filters out non-standard subroles (palettes, sheets, inspectors), the menu-bar
    /// owner row, and OptionTab's own windows.
    ///
    /// - Parameter app: The running application to enumerate.
    /// - Returns: An array of `AppWindow` values, or an empty array when AX access fails.
    func windows(for app: NSRunningApplication) async -> [AppWindow] {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 1. Enumerate AX windows on the current Space and index them by CGWindowID.
        let axWindows: [AXUIElement] = attribute(of: appElement, key: kAXWindowsAttribute) ?? []
        let focusedWindow: AXUIElement? = attribute(of: appElement, key: kAXFocusedWindowAttribute)

        var axByCGID: [CGWindowID: AXUIElement] = [:]
        for axWindow in axWindows {
            var cgID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &cgID) == .success, cgID != 0 {
                axByCGID[cgID] = axWindow
            }
        }

        // 2. Enumerate CG windows across all Spaces for this PID.
        let cgOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let cgInfos = (CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]]) ?? []

        var result: [AppWindow] = []
        var seenCGIDs = Set<CGWindowID>()
        var droppedForMissingName = 0

        for info in cgInfos {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                continue
            }
            // Layer 0 is the normal window layer. Higher layers are menu bar items, dock, etc.
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let cgID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            if !seenCGIDs.insert(cgID).inserted { continue }

            let axElement = axByCGID[cgID]

            // When AX is available, enforce the standard-window subrole filter.
            // CG-only windows (other Spaces) keep the entry — we can't inspect their subrole
            // without an AX element, but the layer-0 filter already excludes most non-windows.
            if let ax = axElement,
               let subrole: String = attribute(of: ax, key: kAXSubroleAttribute),
               subrole != kAXStandardWindowSubrole {
                continue
            }

            let axTitle: String? = axElement.flatMap { attribute(of: $0, key: kAXTitleAttribute) }
            let cgTitle = info[kCGWindowName as String] as? String
            let title = [axTitle, cgTitle]
                .compactMap { $0 }
                .first(where: { !$0.isEmpty }) ?? "Untitled"

            // CG-only entries (no AX element) need stricter filtering: layer 0 alone surfaces
            // many helper / compositing surfaces (Safari web content layers, toolbar trackers,
            // shadow drawers, etc.) which appear as "Untitled" rows in the switcher.
            //
            // A real off-Space document window has:
            //   - a non-empty `kCGWindowName` (requires Screen Recording permission since 10.15;
            //     without that permission the title is always nil and off-Space windows cannot
            //     reliably be distinguished from helpers, so we drop them entirely),
            //   - a meaningful on-screen size,
            //   - alpha > 0,
            //   - sharing state != none.
            if axElement == nil {
                let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
                let sharing = (info[kCGWindowSharingState as String] as? Int) ?? 1
                let bounds = (info[kCGWindowBounds as String] as? [String: CGFloat]) ?? [:]
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0

                guard alpha > 0,
                      sharing != 0,
                      width >= 100, height >= 100,
                      let name = cgTitle, !name.isEmpty else {
                    if cgTitle == nil || cgTitle?.isEmpty == true {
                        droppedForMissingName += 1
                    }
                    continue
                }
            }

            let isMinimized: Bool = axElement.flatMap { attribute(of: $0, key: kAXMinimizedAttribute) } ?? false

            let isFocused: Bool = {
                guard let focused = focusedWindow, let ax = axElement else { return false }
                return CFEqual(ax, focused)
            }()

            result.append(AppWindow(
                id: Int(cgID),
                pid: pid,
                axElement: axElement,
                cgWindowID: cgID,
                title: title,
                isMinimized: isMinimized,
                isFocused: isFocused
            ))
        }

        // 3. Append any AX windows that the CG enumeration missed (rare, but keeps parity).
        for axWindow in axWindows {
            var cgID: CGWindowID = 0
            let hasCGID = _AXUIElementGetWindow(axWindow, &cgID) == .success && cgID != 0
            if hasCGID, seenCGIDs.contains(cgID) { continue }

            guard let subrole: String = attribute(of: axWindow, key: kAXSubroleAttribute),
                  subrole == kAXStandardWindowSubrole else {
                continue
            }

            let title: String = attribute(of: axWindow, key: kAXTitleAttribute) ?? "Untitled"
            let isMinimized: Bool = attribute(of: axWindow, key: kAXMinimizedAttribute) ?? false

            var ptr: UInt = 0
            withUnsafeBytes(of: axWindow) { ptr = $0.load(as: UInt.self) }
            let fallbackID = hasCGID ? Int(cgID) : Int(bitPattern: ptr)

            let isFocused: Bool = {
                guard let focused = focusedWindow else { return false }
                return CFEqual(axWindow, focused)
            }()

            result.append(AppWindow(
                id: fallbackID,
                pid: pid,
                axElement: axWindow,
                cgWindowID: hasCGID ? cgID : nil,
                title: title.isEmpty ? "Untitled" : title,
                isMinimized: isMinimized,
                isFocused: isFocused
            ))
        }

        // 4. Put focused window first, then preserve enumeration order.
        result.sort { $0.isFocused && !$1.isFocused }

        if droppedForMissingName > 0 {
            print("[AX] dropped \(droppedForMissingName) off-Space window(s) without a CG name — Screen Recording permission may be required to read titles of windows on other desktops")
        }
        print("[AX] found \(result.count) standard window(s) for \(app.localizedName ?? "?") (AX: \(axByCGID.count), CG-only: \(result.count - axByCGID.count))")
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
