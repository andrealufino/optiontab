//
//  LaunchAtLoginService.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import Foundation
import ServiceManagement


/// Manages "Launch at Login" state via `SMAppService.mainApp`.
@Observable
@MainActor
final class LaunchAtLoginService {

    // MARK: Properties

    /// Whether the app is currently registered to launch at login.
    private(set) var isEnabled: Bool = false


    // MARK: Initialization

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
        print("[Launch] launch at login: \(isEnabled)")
    }


    // MARK: Public Methods

    /// Toggles launch-at-login registration on or off.
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }


    // MARK: Private Methods

    /// Registers the app with Login Items.
    private func enable() {
        do {
            try SMAppService.mainApp.register()
            isEnabled = true
            print("[Launch] registered for launch at login")
        } catch {
            print("[Launch] failed to register: \(error)")
        }
    }

    /// Unregisters the app from Login Items.
    private func disable() {
        do {
            try SMAppService.mainApp.unregister()
            isEnabled = false
            print("[Launch] unregistered from launch at login")
        } catch {
            print("[Launch] failed to unregister: \(error)")
        }
    }
}
