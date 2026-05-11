//
//  AXPrivate.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 04/05/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import ApplicationServices
import CoreGraphics
import Foundation


// MARK: - Private Accessibility SPI

/// Returns the `CGWindowID` associated with an AX window element.
///
/// Undocumented SPI exported by `ApplicationServices`. The only known way to map an
/// `AXUIElement` to a `CGWindowID` without resorting to fragile heuristics. Stable
/// for years and used by AltTab, Hammerspoon, Rectangle.
@_silgen_name("_AXUIElementGetWindow")
private nonisolated func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError


/// Returns the `CGWindowID` for an AX window element, or `nil` when the SPI call fails.
///
/// - Parameter element: The AX window element to query.
/// - Returns: The matching `CGWindowID`, or `nil` if the SPI is unavailable or returns an error.
nonisolated func axCGWindowID(of element: AXUIElement) -> CGWindowID? {
    var windowID: CGWindowID = 0
    let result = _AXUIElementGetWindow(element, &windowID)
    return result == .success ? windowID : nil
}


// MARK: - SkyLight / SLPS Private SPI

/// Type aliases for SkyLight handles, mirroring AltTab/DockDoor declarations.
typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64
typealias CGSSpaceMask = UInt64
typealias AXUIElementID = UInt64

/// All-spaces mask passed to `CGSCopySpacesForWindows`.
nonisolated let kCGSAllSpacesMask: CGSSpaceMask = 0xFFFF_FFFF_FFFF_FFFF

/// Returns the calling process's main connection to the Window Server.
///
/// Initialising the global `CGS_CONNECTION` at module load forces the SkyLight
/// client library to register the app as a Window-Server peer. Without this
/// registration, several SLPS APIs return `.success` but become silent no-ops
/// — the symptom we observed before adding it. AltTab declares this exactly
/// the same way.
@_silgen_name("CGSMainConnectionID")
nonisolated func CGSMainConnectionID() -> CGSConnectionID

/// The shared SkyLight connection ID for this process.
///
/// Initialised at module load. The value itself is rarely consumed directly by
/// our code, but the side effect of obtaining it is required for SLPS calls to
/// take effect on macOS 14+.
nonisolated let CGS_CONNECTION: CGSConnectionID = CGSMainConnectionID()

/// Modes accepted by `_SLPSSetFrontProcessWithOptions`.
///
/// `userGenerated` is the flag passed when a real user action raises a window;
/// it triggers the cross-Space switch animation when the target window lives on
/// a different Space than the active one.
enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

/// Brings a window owned by `psn` to the front, performing the Space switch when needed.
///
/// Undocumented SPI exported by SkyLight. This is the call AltTab uses to raise a
/// window across Spaces using only its `CGWindowID`. Together with
/// `SLPSPostEventRecordTo` (used to send fake mouseDown/mouseUp events that mark
/// the window as key) this is sufficient to focus a window that AX cannot reach
/// because it lives on another Space.
@_silgen_name("_SLPSSetFrontProcessWithOptions")
@discardableResult
nonisolated func _SLPSSetFrontProcessWithOptions(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ wid: CGWindowID,
    _ mode: SLPSMode.RawValue
) -> CGError

/// Posts an event record directly to the front process via SkyLight.
///
/// Used in tandem with `_SLPSSetFrontProcessWithOptions` to make the window the
/// key window. The 0xf8-byte payload encodes a synthetic mouse event whose
/// target window ID is patched in at offset 0x3c.
@_silgen_name("SLPSPostEventRecordTo")
@discardableResult
nonisolated func SLPSPostEventRecordTo(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError

/// Resolves a `ProcessSerialNumber` from a Unix `pid_t`.
///
/// Re-exposes the legacy Carbon `GetProcessForPID` symbol that the official Swift
/// overlay marks as unavailable on macOS. The C function still ships in the
/// `ApplicationServices` framework and is used internally by the system; AltTab
/// and Hammerspoon depend on it for cross-Space raise.
@_silgen_name("GetProcessForPID")
@discardableResult
nonisolated func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus


// MARK: - Cross-Space Discovery SPI

/// Creates an `AXUIElement` from a 20-byte remote token.
///
/// Used by AltTab and DockDoor for brute-force enumeration of windows that live
/// on Spaces other than the current one — the only known way to obtain a usable
/// AX element for cross-Space windows on macOS 14+. Returns `nil` for invalid
/// tokens (most of the 1000 attempted IDs).
@_silgen_name("_AXUIElementCreateWithRemoteToken")
nonisolated func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

/// Returns the Space IDs hosting the given window IDs.
///
/// `mask` is typically `kCGSAllSpacesMask` to query every Space. Optional CFArray
/// return reflects that the SPI may yield `nil` when Screen Recording is denied
/// or the window is not enumerable.
@_silgen_name("CGSCopySpacesForWindows")
nonisolated func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: CGSSpaceMask, _ windowIDs: CFArray) -> CFArray?

/// Returns the per-display managed Spaces dictionary, used to determine the
/// currently active Space on each display.
@_silgen_name("CGSCopyManagedDisplaySpaces")
nonisolated func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

/// Reads the window-server level of a given window.
///
/// Used to discriminate real top-level windows from overlays, palettes, and
/// — most importantly — Finder's tab "pages" that share a CGWindowID range
/// with their parent window but live below `kCGNormalWindowLevel`.
@_silgen_name("CGSGetWindowLevel")
@discardableResult
nonisolated func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: UInt32, _ outLevel: UnsafeMutablePointer<Int32>) -> Int32


// MARK: - Sendable Bridges

/// Wraps an `AXUIElement` so it can cross actor boundaries under Swift 6 strict
/// concurrency.
///
/// `AXUIElement` is a CFType and not `Sendable`. AX read/write calls are however
/// thread-safe per Apple's documentation, so the conformance is sound. The box
/// is intentionally minimal — consumers reach inside via `.element` only on the
/// actor that needs to perform the AX call.
nonisolated struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}
