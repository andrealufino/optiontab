//
//  OnboardingPanel.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 19/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// A floating, key-capable panel hosting the onboarding SwiftUI view.
///
/// Unlike `OverlayPanel` (which is `.nonactivatingPanel` because the switcher
/// must not steal focus), this panel is designed to become key and receive
/// clicks / keyboard input. Window level is `.floating` so it sits above
/// normal application windows even though OptionTab runs as `.accessory`.
final class OnboardingPanel: NSPanel {

    // MARK: NSWindow Overrides

    /// Returns `true` so buttons and links in the onboarding receive events.
    override var canBecomeKey: Bool { true }

    /// Returns `true` so the panel participates in main-window behavior
    /// (standard close / miniaturize interactions).
    override var canBecomeMain: Bool { true }
}
