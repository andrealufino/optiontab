//
//  OverlayPanel.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import Foundation


/// A non-activating floating panel used as the switcher overlay.
///
/// The panel is borderless, shadow-bearing, and set to `.floating` level
/// so it appears above normal windows without stealing focus from the
/// frontmost application.
final class OverlayPanel: NSPanel {

    // MARK: Initialization

    /// Creates the overlay panel with the correct style mask and window level.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
    }


    // MARK: NSWindow Overrides

    /// Returns `true` so the panel can receive key events while non-activating.
    override var canBecomeKey: Bool { true }

    /// Returns `true` to allow the panel to become main if needed.
    override var canBecomeMain: Bool { false }


    // MARK: Private Methods

    /// Applies panel appearance settings.
    ///
    /// Shadow is drawn by SwiftUI on the rounded shape itself; the window-level
    /// shadow is disabled because it would otherwise render a rectangular shadow
    /// around the full content frame, bleeding past the rounded glass corners.
    private func configure() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }

    /// Resizes the panel to fit its hosting view's intrinsic content size.
    ///
    /// The content size includes the SwiftUI view's outer padding (reserved
    /// for shadow bleed), so the panel frame must match exactly to avoid
    /// clipping the shadow at the edges.
    func sizeToFit() {
        guard let contentView else { return }
        let size = contentView.fittingSize
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let clampedHeight = min(size.height, maxHeight)
        setContentSize(NSSize(width: size.width, height: max(clampedHeight, 80)))
    }
}
