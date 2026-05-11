//
//  WindowRaiser.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import ApplicationServices
import Foundation


/// Raises a target window across three paths.
///
/// - **A — AX-only**: window is on the active Space and has no `CGWindowID`.
///   A `kAXRaiseAction` plus `app.activate()` is enough.
/// - **B — Hybrid (SLPS + AX)**: we have both an AX element and a `CGWindowID`.
///   Mirrors **AltTab** `Window.focus()` 1:1: SLPS set-front + make-key-window
///   event pair + `kAXRaiseAction`. Nothing else. No `kAXMainWindowAttribute`,
///   no `kAXFocusedAttribute`, no `app.activate()`. AltTab is a strict
///   `.accessory` app like us and runs this sequence on a background
///   accessibility queue.
/// - **C — SLPS-only fallback**: rare, no AX element available. Best-effort.
@MainActor
struct WindowRaiser {

    // MARK: Private Properties

    /// Background queue for SkyLight + AX raise calls.
    ///
    /// AltTab uses `BackgroundWork.accessibilityCommandsQueue` for the same
    /// sequence; running on the main thread leaves us susceptible to
    /// "raised-but-not-key" greying because the system processes the raise
    /// before our main-actor work fully releases focus.
    private static let raiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.andrealufino.optiontab.raise"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: Public Methods

    /// Raises the specified window and brings its application to the foreground.
    ///
    /// Selects path A, B, or C automatically based on which identifiers the
    /// window carries. Deminimizes first when needed.
    ///
    /// - Parameter window: The `AppWindow` to raise.
    func raise(_ window: AppWindow) {
        #if DEBUG
        print("[Raise] target='\(window.title)' minimized=\(window.isMinimized) cgID=\(window.cgWindowID.map(String.init) ?? "nil") hasAX=\(window.axElement != nil)")
        #endif

        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("[Raise] no NSRunningApplication for pid \(window.pid)")
            return
        }

        if let element = window.axElement, window.isMinimized {
            deminimize(element: element, title: window.title)
        }

        // Path A: AX-only — current Space, no CG identifier needed.
        if let element = window.axElement, window.cgWindowID == nil {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            app.activate()
            return
        }

        // Path B: Hybrid — AX element resolved (standard or brute-force) plus CGWindowID.
        if let element = window.axElement, let cgID = window.cgWindowID {
            let box = AXElementBox(element: element)
            let pid = window.pid
            let title = window.title
            Self.raiseQueue.addOperation {
                Self.performHybridRaise(elementBox: box, cgWindowID: cgID, pid: pid, title: title)
            }
            return
        }

        // Path C: SLPS-only fallback (rare after brute-force pivot).
        if let cgID = window.cgWindowID {
            let pid = window.pid
            let title = window.title
            Self.raiseQueue.addOperation {
                Self.performSLPSOnlyRaise(cgWindowID: cgID, pid: pid, title: title)
            }
        }
    }


    // MARK: Private — Hybrid Path

    /// Raises a window via AltTab `Window.focus()` 1:1 sequence.
    ///
    /// Runs on `raiseQueue` (background, userInteractive QoS), mirroring
    /// AltTab's `BackgroundWork.accessibilityCommandsQueue` dispatch:
    ///
    /// 1. Resolve `ProcessSerialNumber` from pid.
    /// 2. `_SLPSSetFrontProcessWithOptions` with `SLPSMode.userGenerated`.
    /// 3. Post the make-key-window event pair.
    /// 4. `kAXRaiseAction`. Nothing else.
    ///
    /// Specifically NOT done (AltTab does not do them either):
    /// - `kAXMainWindowAttribute = true`
    /// - `kAXFocusedAttribute = true`
    /// - `app.activate()` (neither before nor after)
    ///
    /// Each of those extras introduced a regression in earlier attempts
    /// (snap-back to previous app, greyed-out destination chrome). AltTab is a
    /// strict `.accessory` app and ships this exact sequence on macOS 14+
    /// without issue — provided the calling overlay relinquishes
    /// `canBecomeKey` before its `orderOut`, which we handle in
    /// `OverlayController.dismissPanelImmediate()`.
    private nonisolated static func performHybridRaise(elementBox: AXElementBox, cgWindowID: CGWindowID, pid: pid_t, title: String) {
        var psn = ProcessSerialNumber()
        let psnResult = _GetProcessForPID(pid, &psn)
        guard psnResult == noErr else {
            print("[Raise] GetProcessForPID failed for pid \(pid): \(psnResult)")
            return
        }

        let frontResult = _SLPSSetFrontProcessWithOptions(&psn, cgWindowID, SLPSMode.userGenerated.rawValue)
        if frontResult != .success {
            print("[Raise] _SLPSSetFrontProcessWithOptions failed cgID \(cgWindowID): \(frontResult)")
        }

        postMakeKeyWindowEvents(psn: &psn, cgWindowID: cgWindowID)

        let raised = AXUIElementPerformAction(elementBox.element, kAXRaiseAction as CFString)
        #if DEBUG
        print("[Raise] hybrid '\(title)' cgID=\(cgWindowID) raise=\(raised.rawValue)")
        #else
        _ = raised
        #endif
    }


    // MARK: Private — SLPS-Only Fallback

    /// Best-effort raise when only the `CGWindowID` is available.
    private nonisolated static func performSLPSOnlyRaise(cgWindowID: CGWindowID, pid: pid_t, title: String) {
        var psn = ProcessSerialNumber()
        let psnResult = _GetProcessForPID(pid, &psn)
        guard psnResult == noErr else { return }
        _SLPSSetFrontProcessWithOptions(&psn, cgWindowID, SLPSMode.userGenerated.rawValue)
        postMakeKeyWindowEvents(psn: &psn, cgWindowID: cgWindowID)
        #if DEBUG
        print("[Raise] SLPS-only '\(title)' cgID=\(cgWindowID)")
        #endif
    }


    // MARK: Private — Make-Key Event Payload

    /// Posts the SkyLight event payload that marks `cgWindowID` as the key window.
    ///
    /// The 0xf8-byte buffer is shaped as a fake mouse-down/mouse-up event pair:
    /// - byte 0x04 holds the payload length (0xf8)
    /// - byte 0x08 carries the event phase (0x01 = down, 0x02 = up)
    /// - byte 0x3a is a fixed marker (0x10)
    /// - bytes 0x3c..<0x40 carry the target `CGWindowID` little-endian
    /// - bytes 0x20..<0x30 are filled with 0xff
    ///
    /// Verified byte-for-byte against AltTab `Window.makeKeyWindow`.
    private nonisolated static func postMakeKeyWindowEvents(psn: UnsafeMutablePointer<ProcessSerialNumber>, cgWindowID: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var localID = cgWindowID
        memcpy(&bytes[0x3c], &localID, MemoryLayout<CGWindowID>.size)
        memset(&bytes[0x20], 0xff, 0x10)

        bytes[0x08] = 0x01
        SLPSPostEventRecordTo(psn, &bytes)
        bytes[0x08] = 0x02
        SLPSPostEventRecordTo(psn, &bytes)
    }


    // MARK: Private — AX Helpers

    /// Sets `kAXMinimizedAttribute` to `false` on a window element.
    ///
    /// - Parameters:
    ///   - element: The minimized window element to restore.
    ///   - title: The window title, used only for logging.
    private func deminimize(element: AXUIElement, title: String) {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            false as CFBoolean
        )
        if result != .success {
            print("[Raise] failed to deminimize '\(title)': \(result.rawValue)")
        }
    }
}
