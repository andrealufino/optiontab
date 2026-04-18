//
//  PermissionsService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Monitors Accessibility permission state and notifies observers when it changes.
@Observable
@MainActor
final class PermissionsService {

    // MARK: Properties

    /// Whether `AXIsProcessTrusted()` currently returns `true`.
    private(set) var isAccessibilityGranted: Bool = false

    /// Fires when permission transitions from denied → granted (used by `AppDelegate` to register hotkey).
    var onPermissionGranted: (() -> Void)?

    /// Fires when permission transitions from granted → denied (used by `AppDelegate` to tear down monitors).
    var onPermissionRevoked: (() -> Void)?

    private var pollingTask: Task<Void, Never>?


    // MARK: Initialization

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
        print("[Perms] initial state: \(isAccessibilityGranted)")
    }


    // MARK: Public Methods

    /// Starts polling `AXIsProcessTrusted()` every second until the service is stopped.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await checkPermission()
            }
        }
    }

    /// Stops the polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }


    // MARK: Private Methods

    /// Reads the current AX trust state and fires callbacks on transitions.
    private func checkPermission() async {
        let current = AXIsProcessTrusted()
        guard current != isAccessibilityGranted else { return }

        isAccessibilityGranted = current
        print("[Perms] permission changed to: \(current)")

        if current {
            onPermissionGranted?()
        } else {
            onPermissionRevoked?()
        }
    }
}
