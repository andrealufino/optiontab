//
//  HotKeyService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Carbon
import Foundation


/// Registers and manages the global `Option+Tab` Carbon hotkey.
///
/// Carbon's `RegisterEventHotKey` fires even when another app is frontmost,
/// which is required for a global switcher. The hotkey is unregistered on `deinit`.
@MainActor
final class HotKeyService {

    // MARK: Properties

    /// Called on the main thread each time `Option+Tab` is pressed.
    var onHotKeyPressed: (() -> Void)?

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    // Unique ID for the hotkey registration.
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("OPTB"), id: 1)


    // MARK: Initialization

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandlerRef { RemoveEventHandler(handler) }
    }


    // MARK: Public Methods

    /// Registers `Option+Tab` with the Carbon Event Manager.
    ///
    /// Safe to call multiple times; re-registers if already registered.
    func register() {
        unregister()

        // Install the event handler on the application event target.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotKeyService>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in
                    service.handleHotKeyEvent(event)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[HotKey] failed to install event handler: \(status)")
            Unmanaged<HotKeyService>.fromOpaque(selfPtr).release()
            return
        }

        // Option = optionKey (0x0800), Tab = kVK_Tab (0x30)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Tab),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            print("[HotKey] Option+Tab registered")
        } else {
            print("[HotKey] failed to register hotkey: \(registerStatus)")
        }
    }

    /// Unregisters the hotkey and removes the event handler.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            print("[HotKey] Option+Tab unregistered")
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }


    // MARK: Private Methods

    /// Fires `onHotKeyPressed` after verifying the event matches our registered ID.
    ///
    /// - Parameter event: The Carbon `EventRef` received from the event handler.
    private func handleHotKeyEvent(_ event: EventRef?) {
        var receivedID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )

        guard receivedID.id == hotKeyID.id else { return }
        print("[HotKey] Option+Tab fired")
        onHotKeyPressed?()
    }
}


// MARK: - Helpers

/// Converts a 4-character string literal into an `OSType` (FourCharCode).
///
/// - Parameter string: Exactly 4 ASCII characters.
/// - Returns: The corresponding `OSType` value.
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8 {
        result = (result << 8) + OSType(char)
    }
    return result
}
