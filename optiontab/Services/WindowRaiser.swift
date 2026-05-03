//
//  WindowRaiser.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Private SPI used to map an `AXUIElement` window to its `CGWindowID`.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError


/// Raises a target window, unminimizing it first when necessary.
struct WindowRaiser {

    // MARK: Public Methods

    /// Raises the specified window and brings its application to the foreground.
    ///
    /// If the window is minimized, this method deminimizes it before raising.
    /// If the window is on another Space, macOS switches to that Space automatically
    /// when `kAXRaiseAction` is performed on the window's AX element.
    ///
    /// For windows enumerated only via `CGWindowListCopyWindowInfo` (i.e. windows that
    /// live on a different Space and were not exposed by `kAXWindowsAttribute`), no
    /// AX element is available at enumeration time. In that case the raiser falls back
    /// to invoking the window's entry in the application's **Window** menu, which is
    /// the only AX-driven way to make macOS switch to a fullscreen Space owned by
    /// another desktop.
    ///
    /// - Parameter window: The `AppWindow` to raise.
    func raise(_ window: AppWindow) {
        print("[AX] raising window '\(window.title)' (minimized: \(window.isMinimized), hasAX: \(window.axElement != nil))")

        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("[AX] could not find running application for pid \(window.pid)")
            return
        }

        if let axElement = window.axElement {
            if window.isMinimized {
                deminimize(axElement, title: window.title)
            }
            AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            app.activate()
            return
        }

        // No AX element — the window is on another Space. Activate the app first so
        // its menu bar (and Window menu) becomes addressable, then click the matching
        // entry in the Window menu. AXPress on a Window-menu item is the documented
        // AX-level way to focus a window across Spaces; macOS handles the Space switch.
        app.activate()

        if pressWindowMenuItem(forTitle: window.title, pid: window.pid) {
            return
        }

        // Last-resort fallback: re-query AX after activation and try matching by
        // CGWindowID. Often `kAXWindowsAttribute` still excludes off-Space windows,
        // but on some macOS versions / apps the window does become addressable
        // briefly after activation.
        if let cgID = window.cgWindowID {
            raiseByCGWindowID(cgID, pid: window.pid, title: window.title)
        }
    }


    // MARK: Private Methods

    /// Sets `kAXMinimizedAttribute` to `false` on the given AX window element.
    ///
    /// - Parameters:
    ///   - axElement: The minimized window element to restore.
    ///   - title: The window title, used only for diagnostic logging.
    private func deminimize(_ axElement: AXUIElement, title: String) {
        let result = AXUIElementSetAttributeValue(
            axElement,
            kAXMinimizedAttribute as CFString,
            false as CFBoolean
        )
        if result != .success {
            print("[AX] failed to deminimize window '\(title)': \(result.rawValue)")
        }
    }

    /// Searches the application's **Window** menu for an item whose title matches
    /// `title` and performs `AXPress` on it.
    ///
    /// Standard Cocoa apps populate their Window menu with one item per open window,
    /// labelled with the window's title. Pressing the matching item activates that
    /// window and switches Spaces if needed — this works even for fullscreen windows
    /// living on a separate desktop.
    ///
    /// - Parameters:
    ///   - title: The exact window title to look for.
    ///   - pid: The process identifier of the owning application.
    /// - Returns: `true` if a matching menu item was found and pressed, `false` otherwise.
    private func pressWindowMenuItem(forTitle title: String, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarRef = menuBarValue else {
            print("[AX] no menu bar exposed for pid \(pid)")
            return false
        }
        let menuBarElement = menuBarRef as! AXUIElement

        var menusValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &menusValue) == .success,
              let menus = menusValue as? [AXUIElement] else {
            return false
        }

        // The Window menu is typically titled "Window" in English builds. Some apps
        // localise it; match by title best-effort, falling back to scanning every
        // top-level menu for an item whose title matches the requested window title.
        let windowMenu: AXUIElement? = menus.first { menu in
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menu, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let menuTitle = titleValue as? String else { return false }
            return menuTitle == "Window" || menuTitle == "Fenster" || menuTitle == "Fenêtre" || menuTitle == "Ventana" || menuTitle == "Finestra" || menuTitle == "ウインドウ" || menuTitle == "窗口"
        }

        let candidateMenus: [AXUIElement] = windowMenu.map { [$0] } ?? menus

        for menu in candidateMenus {
            if let item = findMenuItem(in: menu, matchingTitle: title) {
                let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                if result == .success {
                    print("[AX] pressed Window menu item for '\(title)'")
                    return true
                } else {
                    print("[AX] AXPress failed on Window menu item: \(result.rawValue)")
                }
            }
        }

        print("[AX] no Window menu item matched title '\(title)'")
        return false
    }

    /// Recursively searches a menu element for a menu item whose `kAXTitleAttribute`
    /// equals `title`.
    ///
    /// - Parameters:
    ///   - element: The menu or menu-item element to search from.
    ///   - title: The exact title to match.
    /// - Returns: The first matching `AXUIElement`, or `nil`.
    private func findMenuItem(in element: AXUIElement, matchingTitle title: String) -> AXUIElement? {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success,
               let childTitle = titleValue as? String,
               childTitle == title {
                return child
            }
            if let nested = findMenuItem(in: child, matchingTitle: title) {
                return nested
            }
        }
        return nil
    }

    /// Best-effort raise of a window identified only by its `CGWindowID`.
    ///
    /// Re-enumerates the app's AX windows and matches each one's `CGWindowID` via
    /// `_AXUIElementGetWindow`. When a match is found, performs `kAXRaiseAction` on it.
    ///
    /// - Parameters:
    ///   - cgID: The Core Graphics identifier of the window to raise.
    ///   - pid: The process identifier of the owning application.
    ///   - title: Window title for diagnostic logging.
    private func raiseByCGWindowID(_ cgID: CGWindowID, pid: pid_t, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else {
            print("[AX] post-activation re-query failed for pid \(pid) (window '\(title)')")
            return
        }

        for axWindow in axWindows {
            var foundID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &foundID) == .success, foundID == cgID {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                print("[AX] raised '\(title)' via post-activation CGID match")
                return
            }
        }

        print("[AX] could not match CGWindowID \(cgID) to an AX element after activation (window '\(title)')")
    }
}
