//
//  CGWindowSnapshot.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 04/05/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import CoreGraphics
import Foundation


// MARK: - CGWindowSnapshot

/// A lightweight, value-typed view of a single window record returned by `CGWindowListCopyWindowInfo`.
///
/// The snapshot exposes only the fields needed for cross-Space window discovery and
/// is `Sendable` so it can be returned from a `Task.detached` boundary into the main actor.
struct CGWindowSnapshot: Sendable {

    // MARK: Properties

    /// The unique window identifier assigned by the window server.
    let windowID: CGWindowID

    /// The window title as reported by Core Graphics, or `"Untitled"` when missing or empty.
    let title: String

    /// The window bounds in screen coordinates.
    let bounds: CGRect

    /// The opacity of the window, ranging from `0.0` (invisible) to `1.0` (fully opaque).
    let alpha: Double

    /// The owning process identifier.
    let ownerPID: pid_t

    /// Whether `kCGWindowIsOnscreen` reports the window as currently visible.
    ///
    /// Used by the ghost-window filter: a window that is on the active Space
    /// but not onscreen is typically a transient AppKit "App Preview" or a
    /// stale Finder desktop helper, and should be hidden from the switcher.
    let isOnscreen: Bool
}


// MARK: - CGWindowSnapshotProvider

/// Enumerates window snapshots from Core Graphics.
///
/// Used to complement the Accessibility window list with windows that live on Spaces
/// other than the active one — including fullscreen windows on dedicated Spaces.
///
/// On macOS 14+ `CGWindowListCopyWindowInfo` returns full information for windows
/// of other processes only when the calling app holds Screen Recording permission.
/// Without permission the call still succeeds but returns redacted entries (empty
/// titles, sometimes missing bounds) and may omit other-process windows entirely.
/// Callers should gate this provider behind `PermissionsService.isScreenRecordingGranted`.
enum CGWindowSnapshotProvider {

    // MARK: Public Methods

    /// Returns the standard windows owned by `pid`, including those on other Spaces.
    ///
    /// Filters applied:
    /// - `kCGWindowOwnerPID == pid`
    /// - `kCGWindowAlpha > 0` (drops fully-transparent overlays)
    /// - bounds at least 100×50 (matches AltTab's heuristic; drops Finder desktop
    ///   icons which appear as ~64×64 windows owned by Finder)
    ///
    /// The window-layer filter is intentionally **not** applied: fullscreen windows
    /// can carry layer values different from `0`, and filtering by pid already
    /// excludes Dock, status bar, and other system surfaces (those run in separate
    /// processes).
    ///
    /// `kCGWindowListOptionAll` is required because `kCGWindowListOptionOnScreenOnly`
    /// excludes windows on Spaces other than the current one — exactly the data we
    /// need to recover.
    ///
    /// Marked `nonisolated` so it can run from a `Task.detached` boundary off the
    /// main actor — `CGWindowListCopyWindowInfo` is thread-safe and the returned
    /// snapshots are `Sendable`.
    ///
    /// - Parameter pid: The process identifier of the application to enumerate.
    /// - Returns: An array of `CGWindowSnapshot` values, possibly empty.
    nonisolated static func snapshots(for pid: pid_t) -> [CGWindowSnapshot] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[CG] CGWindowListCopyWindowInfo returned nil for pid \(pid)")
            return []
        }

        var result: [CGWindowSnapshot] = []
        result.reserveCapacity(8)

        for entry in raw {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else {
                continue
            }
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0 else { continue }

            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            guard bounds.width > 100, bounds.height > 50 else { continue }

            let rawTitle = entry[kCGWindowName as String] as? String ?? ""
            let title = rawTitle.isEmpty ? "Untitled" : rawTitle
            let isOnscreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            result.append(CGWindowSnapshot(
                windowID: windowID,
                title: title,
                bounds: bounds,
                alpha: alpha,
                ownerPID: ownerPID,
                isOnscreen: isOnscreen
            ))
        }

        return result
    }
}


// MARK: - Spaces Helpers

/// Returns the set of Space IDs currently active across all displays.
///
/// Mirrors DockDoor `WindowDiscoveryShared.swift::currentActiveSpaceIDs()`.
/// Reads the per-display managed Spaces dictionary; returns an empty set when
/// the SPI is unavailable (e.g. Screen Recording denied), in which case the
/// ghost-window filter degrades silently — windows are kept rather than dropped.
nonisolated func currentActiveSpaceIDs() -> Set<Int> {
    guard let displays = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [[String: AnyObject]] else {
        return []
    }
    var result = Set<Int>()
    for display in displays {
        if let currentSpace = display["Current Space"] as? [String: AnyObject],
           let spaceID = (currentSpace["ManagedSpaceID"] as? NSNumber)?.intValue {
            result.insert(spaceID)
        }
    }
    return result
}

/// Returns the Space IDs hosting the given window.
///
/// Empty when the SPI is unavailable or the window is not enumerable.
///
/// - Parameter windowID: The window identifier to query.
/// - Returns: An array of `CGSSpaceID`, possibly empty.
nonisolated func cgsSpaces(for windowID: CGWindowID) -> [CGSSpaceID] {
    let array = [NSNumber(value: UInt32(windowID))] as CFArray
    guard let spaces = CGSCopySpacesForWindows(CGS_CONNECTION, kCGSAllSpacesMask, array) as? [NSNumber] else {
        return []
    }
    return spaces.map(\.uint64Value)
}

/// Returns the set of `CGWindowID`s that the window server reports as real
/// top-level windows of `pid`.
///
/// Mirrors DockDoor `WindowDiscoveryShared.swift::getCGWindowCandidates` +
/// the membership check used by `isValidCGWindowCandidate`. AX elements whose
/// resolved `CGWindowID` is missing from this set are typically Finder tab
/// pages — the AX subtree exposes one element per tab even though only the
/// active tab corresponds to a real top-level window. Filtering against this
/// set removes the duplicate "tab" entries from the switcher.
nonisolated func realCGWindowIDs(for pid: pid_t) -> Set<CGWindowID> {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else {
        return []
    }
    var ids = Set<CGWindowID>()
    for entry in raw {
        guard let owner = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner == pid else { continue }
        let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer == 0 else { continue }
        guard let wid = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
        ids.insert(CGWindowID(wid))
    }
    return ids
}

/// Returns `true` when the window's CG level is at least `kCGNormalWindowLevel`.
///
/// Excludes overlays, palettes and other auxiliary surfaces that may share
/// the AX surface but should not appear as switcher targets.
nonisolated func isAtLeastNormalLevel(_ windowID: CGWindowID) -> Bool {
    var level: Int32 = 0
    _ = CGSGetWindowLevel(CGS_CONNECTION, UInt32(windowID), &level)
    let normalLevel = CGWindowLevelForKey(.normalWindow)
    return level >= Int32(normalLevel)
}
