//
//  OptionKeyMonitor.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 13/05/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Tracks Option-key release events system-wide for race detection during overlay loading.
///
/// This monitor runs from app launch and is never stopped, giving `OverlayController`
/// a reliable way to detect whether Option was released while window enumeration was
/// in flight — a window during which `EventMonitorService` is not yet installed.
///
/// Unlike `EventMonitorService`, which is scoped to the overlay lifetime, this
/// service records only a timestamp and exposes it via `consumeReleaseAfter(_:)`.
@Observable
@MainActor
final class OptionKeyMonitor {


    // MARK: Properties

    /// Timestamp of the most recent Option-key release observed.
    private(set) var lastReleaseAt: Date?

    private var monitor: Any?


    // MARK: Public Methods

    /// Installs the always-on global monitor for Option-release detection.
    ///
    /// Idempotent — calling more than once is a no-op.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard !event.modifierFlags.contains(.option) else { return }
            Task { @MainActor [weak self] in
                self?.lastReleaseAt = Date()
            }
        }
        print("[OptionKeyMonitor] global monitor started")
    }

    /// Returns `true` if an Option-release was observed strictly after `since`, then clears the stored timestamp.
    ///
    /// The timestamp is consumed atomically so a single release is reported only once.
    ///
    /// - Parameter since: The reference point to compare against — typically the timestamp captured at the start of `show(for:)`.
    /// - Returns: `true` if a qualifying Option release was observed.
    func consumeReleaseAfter(_ since: Date) -> Bool {
        guard let last = lastReleaseAt, last > since else { return false }
        lastReleaseAt = nil
        return true
    }

    /// Returns `true` if the Option key is currently physically pressed.
    ///
    /// Uses `CGEventSource.flagsState(.combinedSessionState)` which reflects
    /// hardware state, unlike `NSEvent.modifierFlags` which reflects the last
    /// processed event — the latter can be stale after rapid key sequences.
    static func isOptionCurrentlyDown() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }
}
