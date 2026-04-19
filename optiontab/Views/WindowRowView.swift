//
//  WindowRowView.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import SwiftUI


/// A single row in the window switcher list.
///
/// Shows the app icon, app name, window title (with marquee if needed),
/// and a minimized badge when applicable. Highlights when selected.
struct WindowRowView: View {

    // MARK: State & Environment

    let window: AppWindow
    let appName: String
    let appIcon: NSImage?
    let isSelected: Bool
    let index: Int

    var onHover: (Int) -> Void
    var onTap: (AppWindow) -> Void


    // MARK: Computed Properties

    private var iconImage: Image {
        if let icon = appIcon {
            return Image(nsImage: icon)
        }
        return Image(systemName: "app.fill")
    }


    // MARK: Body

    var body: some View {
        HStack(spacing: 12) {
            iconImage
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                MarqueeText(
                    text: window.title,
                    font: .system(size: 11),
                    color: .secondary
                )
                .frame(height: 16)
            }

            Spacer()

            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help("Minimized")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                onHover(index)
            }
        }
        .onTapGesture {
            onTap(window)
        }
    }


    // MARK: Computed Properties

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.25))
                .padding(.horizontal, 6)
        }
    }
}
