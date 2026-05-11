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


/// Monitors Accessibility and Screen Recording permission state and notifies observers when they change.
///
/// Accessibility is required for OptionTab to function at all (window enumeration on the
/// current Space, AX raise actions, global hotkey). Screen Recording is optional and
/// unlocks cross-Space window discovery via `CGWindowListCopyWindowInfo`. The service
/// polls both permissions on a single timer.
@Observable
@MainActor
final class PermissionsService {

    // MARK: Properties

    /// Whether `AXIsProcessTrusted()` currently returns `true`.
    private(set) var isAccessibilityGranted: Bool = false

    /// Whether `CGPreflightScreenCaptureAccess()` currently returns `true`.
    ///
    /// Screen Recording is optional: it enables enumeration of windows that live on
    /// other Spaces (including fullscreen). Without it the app still works but only
    /// shows windows on the active Space.
    private(set) var isScreenRecordingGranted: Bool = false

    /// Fires when accessibility transitions from denied → granted (used by `AppDelegate` to register hotkey).
    var onPermissionGranted: (() -> Void)?

    /// Fires when accessibility transitions from granted → denied (used by `AppDelegate` to tear down monitors).
    var onPermissionRevoked: (() -> Void)?

    /// Fires when Screen Recording state changes in either direction.
    var onScreenRecordingChanged: (() -> Void)?

    private var pollingTask: Task<Void, Never>?


    // MARK: Initialization

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        print("[Perms] initial state — accessibility: \(isAccessibilityGranted), screenRecording: \(isScreenRecordingGranted)")
    }


    // MARK: Public Methods

    /// Starts polling both permission states every second until the service is stopped.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await checkPermissions()
            }
        }
    }

    /// Stops the polling loop.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Requests Screen Recording access from the user.
    ///
    /// On first call this triggers the system TCC prompt. On subsequent calls (after
    /// the user has already chosen) it returns the cached decision without prompting.
    /// When access is denied, callers should open System Settings via
    /// `openScreenRecordingSettings()` to let the user revisit the choice.
    ///
    /// - Returns: `true` if access is now granted, `false` otherwise.
    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        print("[Perms] screen recording request returned: \(granted)")
        // Force an immediate state refresh so observers see the change without
        // waiting for the next polling tick.
        if granted != isScreenRecordingGranted {
            isScreenRecordingGranted = granted
            onScreenRecordingChanged?()
        }
        return granted
    }

    /// Opens the Screen Recording pane in System Settings.
    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }


    // MARK: Private Methods

    /// Reads both AX and Screen Recording trust states and fires callbacks on transitions.
    private func checkPermissions() async {
        let currentAX = AXIsProcessTrusted()
        if currentAX != isAccessibilityGranted {
            isAccessibilityGranted = currentAX
            print("[Perms] accessibility changed to: \(currentAX)")
            if currentAX {
                onPermissionGranted?()
            } else {
                onPermissionRevoked?()
            }
        }

        let currentSC = CGPreflightScreenCaptureAccess()
        if currentSC != isScreenRecordingGranted {
            isScreenRecordingGranted = currentSC
            print("[Perms] screen recording changed to: \(currentSC)")
            onScreenRecordingChanged?()
        }
    }
}
