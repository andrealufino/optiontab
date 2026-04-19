//
//  MenuBarController.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// Manages the `NSStatusItem` menu bar icon and its contextual menu.
///
/// The menu contents adapt to whether Accessibility permission is granted.
/// All actions delegate to callbacks to keep this class free of business logic.
@MainActor
final class MenuBarController {

    // MARK: Callbacks

    /// Called when the user selects "Grant Accessibility…".
    var onOpenOnboarding: (() -> Void)?

    /// Called when the user selects "Launch at Login".
    var onToggleLaunchAtLogin: (() -> Void)?

    /// Called when the user selects "Quit OptionTab".
    var onQuit: (() -> Void)?

    // MARK: Private Properties

    private var statusItem: NSStatusItem?
    private var isAccessibilityGranted: Bool = false
    private var isLaunchAtLoginEnabled: Bool = false


    // MARK: Initialization

    /// Sets up the status item with the default icon.
    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.right.to.line", accessibilityDescription: "OptionTab")
        item.button?.image?.isTemplate = true
        statusItem = item
        rebuildMenu()
        print("[Menu] status item created")
    }


    // MARK: Public Methods

    /// Rebuilds the menu to reflect current permission and login state.
    ///
    /// - Parameters:
    ///   - isAccessibilityGranted: Whether Accessibility permission is currently granted.
    ///   - isLaunchAtLoginEnabled: Whether launch at login is currently active.
    func update(isAccessibilityGranted: Bool, isLaunchAtLoginEnabled: Bool) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled

        // Update icon to reflect permission state
        let iconName = isAccessibilityGranted ? "arrow.right.to.line" : "arrow.right.to.line"
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "OptionTab")
        statusItem?.button?.image?.isTemplate = true

        rebuildMenu()
    }


    // MARK: Private Methods

    /// Constructs and assigns the status item menu from scratch.
    private func rebuildMenu() {
        let menu = NSMenu()

        // Permission warning (only when not granted)
        if !isAccessibilityGranted {
            let warnItem = NSMenuItem(
                title: "⚠ Grant Accessibility…",
                action: #selector(handleOpenOnboarding),
                keyEquivalent: ""
            )
            warnItem.target = self
            menu.addItem(warnItem)
            menu.addItem(.separator())
        }

        // App version label
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionItem = NSMenuItem(title: "OptionTab \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        // Launch at Login
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(handleToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About OptionTab",
            action: #selector(handleAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit OptionTab",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }


    // MARK: Actions

    @objc private func handleOpenOnboarding() {
        onOpenOnboarding?()
    }

    @objc private func handleToggleLaunchAtLogin() {
        onToggleLaunchAtLogin?()
    }

    @objc private func handleAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
