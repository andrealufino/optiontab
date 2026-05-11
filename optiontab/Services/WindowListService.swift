//
//  WindowListService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import CoreGraphics
import Foundation


// MARK: - WindowListService

/// Enumerates the standard windows of an application across every Space.
///
/// On macOS 14+, `kAXWindowsAttribute` returns only the windows on the active
/// Space — we therefore complement it with two cross-Space sources:
///
/// 1. **AX brute-force** via `_AXUIElementCreateWithRemoteToken`: produces real
///    `AXUIElement` handles for windows on other Spaces, allowing standard
///    `kAXRaiseAction` instead of the unreliable SLPS-only path.
/// 2. **Core Graphics** via `CGWindowListCopyWindowInfo`: a safety net for
///    windows the AX brute-force does not find.
///
/// CG-only entries pass through a *ghost-window* filter that mirrors DockDoor
/// `WindowDiscoveryShared.shouldAcceptWindow(...)`: windows that are reported
/// off-screen yet live on the active Space (the typical "App Preview" / Finder
/// transient) are dropped before reaching the switcher.
@Observable
@MainActor
final class WindowListService {

    // MARK: Private Properties

    /// Caches brute-force results per pid for a short TTL so consecutive
    /// `Option+Tab` presses do not pay the 1000-call cost again.
    private let bruteForceCache = BruteForceCache()


    // MARK: Public Methods

    /// Returns the list of standard windows for `app`, ordered most-relevant first.
    ///
    /// - Parameters:
    ///   - app: The running application to enumerate.
    ///   - includeOtherSpaces: When `true`, augments the standard AX list with
    ///     brute-force AX discovery and CG-only fallback entries. Callers should
    ///     pass `PermissionsService.isScreenRecordingGranted`.
    /// - Returns: An array of `AppWindow` values, possibly empty.
    func windows(for app: NSRunningApplication, includeOtherSpaces: Bool) async -> [AppWindow] {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Standard AX enumeration — windows on the active Space only.
        let axStandardElements: [AXUIElement] = readAttribute(of: appElement, key: kAXWindowsAttribute) ?? []
        let focusedElement: AXUIElement? = readAttribute(of: appElement, key: kAXFocusedWindowAttribute)

        // Real top-level CGWindowIDs for this pid, used to drop AX entries that
        // correspond to Finder tabs / AppKit "tab pages" (they have an AX element
        // each, but only the active tab carries a real CGWindowID at layer 0).
        let realIDs = await Task.detached(priority: .userInitiated) {
            realCGWindowIDs(for: pid)
        }.value

        let axStandardEntries = buildEntries(
            from: axStandardElements,
            pid: pid,
            focused: focusedElement,
            source: .axStandard,
            realCGWindowIDs: realIDs
        )

        guard includeOtherSpaces else {
            print("[WindowList] \(axStandardEntries.count) AX-std for \(app.localizedName ?? "?") (CG augmentation disabled)")
            return sorted(axStandardEntries)
        }

        // Brute-force AX cross-Space, with cache.
        let bruteBoxes: [AXElementBox]
        if let cached = bruteForceCache.get(pid) {
            bruteBoxes = cached
        } else {
            let snapshot = await Task.detached(priority: .userInitiated) {
                axBruteForceWindows(for: pid)
            }.value
            bruteForceCache.set(pid, boxes: snapshot)
            bruteBoxes = snapshot
        }
        let bruteEntries = buildEntries(
            from: bruteBoxes.map(\.element),
            pid: pid,
            focused: nil,
            source: .axBrute,
            realCGWindowIDs: realIDs
        )

        #if DEBUG
        // Diagnostic counts for issue #2 brute-force triage.
        let bruteWithCG = bruteEntries.filter { $0.cgWindowID != nil }.count
        let bruteWithoutCG = bruteEntries.count - bruteWithCG
        print("[BruteForce] pid=\(pid) accepted=\(bruteEntries.count) (withCG=\(bruteWithCG) withoutCG=\(bruteWithoutCG)) realCGIDs=\(realIDs.sorted())")

        // Dump AX-std entries so we can see if cgID matches the brute-force
        // entries (dedup hinges on cgID equality).
        for entry in axStandardEntries {
            print("[AXStd] pid=\(pid) title='\(entry.title)' cgID=\(entry.cgWindowID.map(String.init) ?? "nil") focused=\(entry.isFocused)")
        }
        #endif

        // Dedup AX (standard ∪ brute) by CGWindowID with pointer fallback.
        let dedupedAX = dedupByWindowID(axStandardEntries + bruteEntries)
        let knownCGIDs: Set<CGWindowID> = Set(dedupedAX.compactMap(\.cgWindowID))
        #if DEBUG
        print("[Dedup] pid=\(pid) before=\(axStandardEntries.count + bruteEntries.count) after=\(dedupedAX.count) cgIDs=\(dedupedAX.map { $0.cgWindowID.map(String.init) ?? "nil" })")
        #endif

        // CG-only fallback for whatever AX still misses.
        let cgSnapshots = await Task.detached(priority: .userInitiated) {
            CGWindowSnapshotProvider.snapshots(for: pid)
        }.value
        let activeSpaces = currentActiveSpaceIDs()
        let isHidden = app.isHidden

        var cgOnlyEntries: [AppWindow] = []
        for snapshot in cgSnapshots where !knownCGIDs.contains(snapshot.windowID) {
            if isGhostWindow(snapshot, activeSpaceIDs: activeSpaces, appIsHidden: isHidden) {
                continue
            }
            cgOnlyEntries.append(AppWindow(
                id: Int(snapshot.windowID),
                pid: pid,
                axElement: nil,
                cgWindowID: snapshot.windowID,
                title: snapshot.title,
                isMinimized: false,
                isFocused: false
            ))
        }

        let combined = dedupedAX + cgOnlyEntries
        let result = sorted(combined)

        print("[WindowList] \(axStandardEntries.count) AX-std, \(bruteEntries.count) AX-brute, \(cgOnlyEntries.count) CG-only for \(app.localizedName ?? "?")")
        return result
    }


    // MARK: Private — Entry Building

    private enum Source {
        case axStandard
        case axBrute
    }

    /// Builds `AppWindow` entries from a list of AX elements.
    ///
    /// AX-standard elements are filtered by subrole == standard. AX-brute elements
    /// are pre-filtered inside `axBruteForceWindows`, so subrole is already known
    /// to be standard or dialog and we skip the redundant read.
    ///
    /// Both sources additionally require:
    /// - the element resolves to a `CGWindowID` via `_AXUIElementGetWindow`, AND
    ///   that `CGWindowID` is present in `realCGWindowIDs` (the layer-0 set of
    ///   real top-level windows). This drops Finder tab pages that share the AX
    ///   surface with their parent window but never receive a top-level CGWindowID.
    /// - the window's CG level is at least `kCGNormalWindowLevel` (drops
    ///   palettes, pop-overs and other auxiliary surfaces).
    ///
    /// AX entries that do NOT have a `CGWindowID` (rare; SPI fallback) are kept
    /// without filter, since we cannot evaluate either condition.
    private func buildEntries(
        from elements: [AXUIElement],
        pid: pid_t,
        focused: AXUIElement?,
        source: Source,
        realCGWindowIDs: Set<CGWindowID>
    ) -> [AppWindow] {
        var entries: [AppWindow] = []
        entries.reserveCapacity(elements.count)
        for element in elements {
            if source == .axStandard {
                guard let subrole: String = readAttribute(of: element, key: kAXSubroleAttribute),
                      subrole == kAXStandardWindowSubrole else {
                    continue
                }
            }

            let cgID = axCGWindowID(of: element)
            if let cgID {
                guard realCGWindowIDs.contains(cgID) else { continue }
                guard isAtLeastNormalLevel(cgID) else { continue }
            }

            let title: String = readAttribute(of: element, key: kAXTitleAttribute) ?? "Untitled"
            let isMinimized: Bool = readAttribute(of: element, key: kAXMinimizedAttribute) ?? false
            let isFocused: Bool = {
                guard let focused else { return false }
                return CFEqual(element, focused)
            }()

            let identifier: Int = {
                if let cgID { return Int(cgID) }
                var ptr: UInt = 0
                withUnsafeBytes(of: element) { ptr = $0.load(as: UInt.self) }
                return Int(bitPattern: ptr)
            }()

            entries.append(AppWindow(
                id: identifier,
                pid: pid,
                axElement: element,
                cgWindowID: cgID,
                title: title.isEmpty ? "Untitled" : title,
                isMinimized: isMinimized,
                isFocused: isFocused
            ))
        }
        return entries
    }


    // MARK: Private — Dedup

    /// Removes duplicate entries that point to the same underlying window.
    ///
    /// Primary key is `cgWindowID` (when both `_AXUIElementGetWindow` succeeded);
    /// fallback key is the entry's `id` (which is the AX pointer for entries
    /// without a CG ID — collisions are extremely unlikely).
    private func dedupByWindowID(_ entries: [AppWindow]) -> [AppWindow] {
        var seenCGIDs = Set<CGWindowID>()
        var seenIDs = Set<Int>()
        var result: [AppWindow] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            if let cgID = entry.cgWindowID {
                if seenCGIDs.contains(cgID) { continue }
                seenCGIDs.insert(cgID)
            } else {
                if seenIDs.contains(entry.id) { continue }
                seenIDs.insert(entry.id)
            }
            result.append(entry)
        }
        return result
    }


    // MARK: Private — Ghost Filter

    /// Returns `true` when a CG-only snapshot is a transient AppKit overlay
    /// (Xcode "App Preview", Finder hidden helpers) rather than a real window.
    ///
    /// Mirrors DockDoor `WindowDiscoveryShared.swift::shouldAcceptWindow`:
    /// the window is a ghost when it is not onscreen, lives on the active
    /// Space, is not minimized, not fullscreen, and the owning app is not
    /// hidden. CG-only entries lack AX, so minimized/fullscreen are assumed
    /// `false` (those states would have produced an AX entry).
    private func isGhostWindow(_ snapshot: CGWindowSnapshot, activeSpaceIDs: Set<Int>, appIsHidden: Bool) -> Bool {
        guard !snapshot.isOnscreen else { return false }
        if appIsHidden { return false }
        let windowSpaces = Set(cgsSpaces(for: snapshot.windowID).map { Int($0) })
        guard !windowSpaces.isEmpty else { return false }
        let isOnActiveSpace = !windowSpaces.isDisjoint(with: activeSpaceIDs)
        return isOnActiveSpace
    }


    // MARK: Private — Sorting

    /// Returns `entries` sorted with the focused AX window first; AX entries
    /// (standard or brute) ahead of CG-only entries; rest in stable order.
    private func sorted(_ entries: [AppWindow]) -> [AppWindow] {
        entries.sorted { lhs, rhs in
            if lhs.isFocused != rhs.isFocused {
                return lhs.isFocused
            }
            switch (lhs.axElement, rhs.axElement) {
            case (.some, .none): return true
            case (.none, .some): return false
            default: return false
            }
        }
    }


    // MARK: Private — AX Attribute Reading

    /// Type-safe wrapper around `AXUIElementCopyAttributeValue`.
    private func readAttribute<T>(of element: AXUIElement, key: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
              let result = value as? T else {
            return nil
        }
        return result
    }
}


// MARK: - BruteForceCache

/// Caches `axBruteForceWindows(for:)` results per pid for a short TTL.
///
/// Avoids paying the 1000-call AX cost when the user mashes `Option+Tab`. The
/// TTL is intentionally short (500 ms): cache covers the burst-press case, and
/// any newly opened window will appear after the next miss.
@MainActor
private final class BruteForceCache {
    private struct Entry {
        let timestamp: Date
        let boxes: [AXElementBox]
    }

    private static let ttl: TimeInterval = 0.5
    private var entries: [pid_t: Entry] = [:]

    func get(_ pid: pid_t) -> [AXElementBox]? {
        guard let entry = entries[pid] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) >= Self.ttl {
            entries.removeValue(forKey: pid)
            return nil
        }
        return entry.boxes
    }

    func set(_ pid: pid_t, boxes: [AXElementBox]) {
        entries[pid] = Entry(timestamp: Date(), boxes: boxes)
    }
}


// MARK: - AX Brute-Force Discovery

/// Brute-force enumerates `AXUIElement`s for a process across every Space.
///
/// Builds a 20-byte remote token whose layout — `[pid: 4][zero: 4][magic: 4][axId: 8]`
/// with `magic == 0x636F_636F` — was reverse-engineered by the AltTab and
/// DockDoor projects. Iterates 1000 candidate `axId` values and keeps elements
/// whose subrole is `kAXStandardWindowSubrole` or `kAXDialogSubrole`.
///
/// Marked `nonisolated` so it can run on a `Task.detached` boundary off the
/// main actor; results are returned wrapped in `AXElementBox` to cross the
/// Sendable boundary cleanly.
///
/// - Parameter pid: The owning process identifier.
/// - Returns: An array of `AXElementBox` values, possibly empty.
nonisolated func axBruteForceWindows(for pid: pid_t) -> [AXElementBox] {
    var token = Data(count: 20)
    var pidValue = pid
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: &pidValue) { Data($0) })
    var zero = Int32(0)
    token.replaceSubrange(4..<8, with: withUnsafeBytes(of: &zero) { Data($0) })
    var magic = Int32(0x636F_636F)
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: &magic) { Data($0) })

    var results: [AXElementBox] = []
    for axId: AXUIElementID in 0..<1000 {
        var idValue = axId
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: &idValue) { Data($0) })
        guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
            continue
        }
        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
              let subrole = subroleValue as? String,
              subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else {
            continue
        }
        #if DEBUG
        debugDumpBruteForceCandidate(element, pid: pid, subrole: subrole, axId: axId)
        if let cgID = axCGWindowID(of: element) {
            let spaces = cgsSpaces(for: cgID)
            print("[BruteForce] axId=\(axId) cgID=\(cgID) spaces=\(spaces)")
        }
        #endif
        results.append(AXElementBox(element: element))
    }
    return results
}


/// Logs `role`, `parent.role`, `title`, `cgID`, `CGS level` for each accepted
/// brute-force candidate. Used to diagnose issue #2 (Finder tab pages and
/// cross-Space sub-elements leaking through the filter).
///
/// Removed before merge / gated behind `#if DEBUG` once the diagnosis is fixed.
nonisolated private func debugDumpBruteForceCandidate(
    _ element: AXUIElement,
    pid: pid_t,
    subrole: String,
    axId: UInt64
) {
    var roleValue: CFTypeRef?
    let role: String
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
       let value = roleValue as? String {
        role = value
    } else {
        role = "<no-role>"
    }

    var parentValue: CFTypeRef?
    let parentRole: String
    if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
       let parentRef = parentValue,
       CFGetTypeID(parentRef) == AXUIElementGetTypeID() {
        let parent = parentRef as! AXUIElement
        var parentRoleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(parent, kAXRoleAttribute as CFString, &parentRoleValue) == .success,
           let value = parentRoleValue as? String {
            parentRole = value
        } else {
            parentRole = "<no-parent-role>"
        }
    } else {
        parentRole = "<no-parent>"
    }

    var titleValue: CFTypeRef?
    let title: String
    if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
       let value = titleValue as? String, !value.isEmpty {
        title = value
    } else {
        title = "<no-title>"
    }

    let cgID = axCGWindowID(of: element)
    let cgIDString = cgID.map(String.init) ?? "nil"
    let levelString: String
    if let cgID {
        var level: Int32 = 0
        _ = CGSGetWindowLevel(CGS_CONNECTION, UInt32(cgID), &level)
        levelString = String(level)
    } else {
        levelString = "n/a"
    }

    print("[BruteForce] pid=\(pid) axId=\(axId) role=\(role) parentRole=\(parentRole) subrole=\(subrole) title='\(title)' cgID=\(cgIDString) level=\(levelString)")
}
