//
//  PermissionsService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import CoreGraphics
import Foundation


/// Monitors Accessibility permission state and notifies observers when it changes.
@Observable
@MainActor
final class PermissionsService {

    // MARK: Properties

    /// Whether `AXIsProcessTrusted()` currently returns `true`.
    private(set) var isAccessibilityGranted: Bool = false

    /// Whether the app currently has Screen Recording permission.
    ///
    /// Required to read `kCGWindowName` for windows on **other Spaces** (fullscreen
    /// windows on a separate desktop). Without it, off-Space windows have no readable
    /// title and `WindowListService` filters them out to avoid showing "Untitled" rows.
    private(set) var isScreenRecordingGranted: Bool = false

    /// Fires when permission transitions from denied → granted (used by `AppDelegate` to register hotkey).
    var onPermissionGranted: (() -> Void)?

    /// Fires when permission transitions from granted → denied (used by `AppDelegate` to tear down monitors).
    var onPermissionRevoked: (() -> Void)?

    private var pollingTask: Task<Void, Never>?


    // MARK: Initialization

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        print("[Perms] initial state: AX=\(isAccessibilityGranted) ScreenRec=\(isScreenRecordingGranted)")
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

    /// Forces an immediate read of `AXIsProcessTrusted()` and fires transition callbacks.
    ///
    /// Useful when the user has just toggled the Accessibility entry in System Settings
    /// and does not want to wait for the next polling tick.
    func refresh() {
        Task { await checkPermission() }
    }

    /// Triggers the system Screen Recording permission prompt (or refreshes the cached state).
    ///
    /// Calling `CGRequestScreenCaptureAccess()` causes macOS to add OptionTab to
    /// **Privacy → Screen Recording** if it is not already there, and prompts the user
    /// the first time. After the user toggles the entry the app must be relaunched for
    /// the new state to take effect.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        print("[Perms] Screen Recording state: \(isScreenRecordingGranted)")
    }


    // MARK: Private Methods

    /// Reads the current AX trust state and fires callbacks on transitions.
    private func checkPermission() async {
        let current = AXIsProcessTrusted()
        let currentScreen = CGPreflightScreenCaptureAccess()

        if currentScreen != isScreenRecordingGranted {
            isScreenRecordingGranted = currentScreen
            print("[Perms] Screen Recording changed to: \(currentScreen)")
        }

        guard current != isAccessibilityGranted else { return }

        isAccessibilityGranted = current
        print("[Perms] Accessibility changed to: \(current)")

        if current {
            onPermissionGranted?()
        } else {
            onPermissionRevoked?()
        }
    }
}
