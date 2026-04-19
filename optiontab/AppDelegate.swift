//
//  AppDelegate.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation
import SwiftUI


/// Application delegate responsible for wiring all services at launch.
///
/// Owns the service graph and coordinates between permissions, hotkey,
/// overlay, and menu bar. All services are injected through callbacks
/// so no singleton references leak between components.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Services

    private let permissionsService = PermissionsService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let hotKeyService = HotKeyService()
    private let overlayController = OverlayController()
    private let menuBarController = MenuBarController()

    /// Panel hosting the onboarding SwiftUI view.
    private var onboardingPanel: OnboardingPanel?


    // MARK: NSApplicationDelegate

    /// Called when the application finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("[App] launched")
        setupMenuBar()
        setupPermissions()

        if permissionsService.isAccessibilityGranted {
            registerHotKey()
        } else {
            showOnboarding()
        }

        permissionsService.startPolling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }


    // MARK: Private — Setup

    /// Wires menu bar callbacks and performs first render.
    private func setupMenuBar() {
        menuBarController.setup()

        menuBarController.onOpenOnboarding = { [weak self] in
            self?.showOnboarding()
        }
        menuBarController.onToggleLaunchAtLogin = { [weak self] in
            guard let self else { return }
            launchAtLoginService.toggle()
            refreshMenuBar()
        }
        menuBarController.onQuit = {
            NSApp.terminate(nil)
        }

        refreshMenuBar()
    }

    /// Wires permission-change callbacks to hotkey registration/deregistration.
    private func setupPermissions() {
        permissionsService.onPermissionGranted = { [weak self] in
            guard let self else { return }
            print("[Perms] permission granted — registering hotkey")
            registerHotKey()
            refreshMenuBar()
            // Close the onboarding window — user will see the "granted" state
            // and decide whether to dismiss or relaunch.
        }
        permissionsService.onPermissionRevoked = { [weak self] in
            guard let self else { return }
            print("[Perms] permission revoked — tearing down hotkey")
            hotKeyService.unregister()
            overlayController.cancel()
            refreshMenuBar()
            showOnboarding()
        }
    }

    /// Registers the hotkey and wires it to the overlay activation flow.
    private func registerHotKey() {
        hotKeyService.onHotKeyPressed = { [weak self] in
            guard let self else { return }
            handleHotKeyPressed()
        }
        hotKeyService.onShiftHotKeyPressed = { [weak self] in
            guard let self else { return }
            handleShiftHotKeyPressed()
        }
        hotKeyService.register()
    }


    // MARK: Private — Actions

    /// Handles `Option+Tab` press by locating the frontmost app and showing the overlay.
    private func handleHotKeyPressed() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            print("[HotKey] no frontmost application")
            return
        }

        // Never switch to ourselves
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            print("[HotKey] frontmost is OptionTab — ignoring")
            return
        }

        Task {
            await overlayController.show(for: frontmost)
        }
    }

    /// Handles `Option+Shift+Tab` by cycling the overlay selection backward.
    ///
    /// When the overlay is not yet visible the press is ignored — backward
    /// cycling only makes sense once the user has opened the switcher with
    /// `Option+Tab`.
    private func handleShiftHotKeyPressed() {
        overlayController.cycleBackwardIfVisible()
    }

    /// Updates the menu bar to reflect current service state.
    private func refreshMenuBar() {
        menuBarController.update(
            isAccessibilityGranted: permissionsService.isAccessibilityGranted,
            isLaunchAtLoginEnabled: launchAtLoginService.isEnabled
        )
    }


    // MARK: Private — Onboarding

    /// Shows the onboarding panel, creating it if needed.
    ///
    /// Activates the app briefly so the panel becomes key even though
    /// OptionTab runs as `.accessory` — activation policy stays `.accessory`
    /// throughout, so no Dock icon appears.
    private func showOnboarding() {
        if let existing = onboardingPanel, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(permissionsService: permissionsService)
        let panel = OnboardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OptionTab — Accessibility Required"
        panel.contentView = NSHostingView(rootView: view)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.center()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        onboardingPanel = panel
        print("[Perms] onboarding shown")
    }
}
