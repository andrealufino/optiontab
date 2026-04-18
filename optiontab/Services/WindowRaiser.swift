//
//  WindowRaiser.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Raises a target window, unminimizing it first when necessary.
struct WindowRaiser {

    // MARK: Public Methods

    /// Raises the specified window and brings its application to the foreground.
    ///
    /// If the window is minimized, this method deminimizes it before raising.
    /// If the window is on another Space, macOS switches to that Space automatically.
    ///
    /// - Parameter window: The `AppWindow` to raise.
    func raise(_ window: AppWindow) {
        print("[AX] raising window '\(window.title)' (minimized: \(window.isMinimized))")

        if window.isMinimized {
            deminimize(window)
        }

        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)

        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("[AX] could not find running application for pid \(window.pid)")
            return
        }

        app.activate()
    }


    // MARK: Private Methods

    /// Sets `kAXMinimizedAttribute` to `false` on the window element.
    ///
    /// - Parameter window: The minimized window to restore.
    private func deminimize(_ window: AppWindow) {
        let result = AXUIElementSetAttributeValue(
            window.axElement,
            kAXMinimizedAttribute as CFString,
            false as CFBoolean
        )
        if result != .success {
            print("[AX] failed to deminimize window '\(window.title)': \(result.rawValue)")
        }
    }
}
