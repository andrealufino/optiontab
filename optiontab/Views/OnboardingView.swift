//
//  OnboardingView.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import SwiftUI


/// The onboarding / permissions window shown when Accessibility access is not granted.
///
/// Polls `PermissionsService` every second and updates the UI when access is granted.
/// Provides a direct link to the Accessibility pane in System Settings.
struct OnboardingView: View {

    // MARK: State & Environment

    let permissionsService: PermissionsService

    @Environment(\.dismiss) private var dismiss


    // MARK: Body

    var body: some View {
        VStack(spacing: 24) {
            if permissionsService.isAccessibilityGranted {
                grantedContent
            } else {
                requestContent
            }
        }
        .padding(32)
        .frame(width: 480, height: 360)
    }


    // MARK: Computed Properties

    private var requestContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Accessibility Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "OptionTab reads window titles and raises windows using macOS Accessibility APIs. " +
                "It also listens for the Option+Tab shortcut globally. " +
                "No window contents are ever captured or recorded."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var grantedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Accessibility Granted")
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "You may need to quit and relaunch OptionTab for the permission to take full effect."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Relaunch") {
                    relaunch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Done") {
                    dismiss()
                }
                .controlSize(.large)
            }
        }
    }


    // MARK: Private Methods

    /// Opens the Accessibility pane in System Settings.
    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Relaunches the app by spawning a new instance then terminating this one.
    private func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
