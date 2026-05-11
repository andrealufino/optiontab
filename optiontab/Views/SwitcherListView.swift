//
//  SwitcherListView.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import SwiftUI


/// The root SwiftUI view hosted inside the overlay panel.
///
/// Renders a vertical container with one `WindowRowView` per window. Uses Liquid Glass
/// on macOS 26+ and `.ultraThinMaterial` on macOS 14–25. Wraps in a `ScrollView` when
/// the list exceeds the available height, and keeps the selected row scrolled into view
/// on every cycle step.
struct SwitcherListView: View {

    // MARK: State & Environment

    let controller: OverlayController

    @State private var appIcon: NSImage? = nil
    @State private var appName: String = ""
    @State private var scrollProxy: ScrollViewProxy? = nil


    // MARK: Body

    var body: some View {
        if #available(macOS 26, *) {
            scrollList
                .background(Color.clear)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22))
                .clipShape(RoundedRectangle(cornerRadius: 22))
        } else {
            scrollList
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    // MARK: Private Views

    /// The scroll container listing all windows, shared between OS-variant styling branches.
    private var scrollList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(controller.windows.enumerated()), id: \.element.id) { index, window in
                        WindowRowView(
                            window: window,
                            appName: appName,
                            appIcon: appIcon,
                            isSelected: controller.selectedIndex == index,
                            index: index,
                            onHover: { hoveredIndex in
                                controller.hoverSelected(hoveredIndex)
                            },
                            onTap: { tappedWindow in
                                Task { await controller.confirmSelection(tappedWindow) }
                            }
                        )
                        .id(index)

                        if index < controller.windows.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(0.3)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollProxy = proxy
                loadAppInfo()
            }
            .onChange(of: controller.selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: 420)
        .scrollContentBackground(.hidden)
    }


    // MARK: Private Methods

    /// Populates `appName` and `appIcon` from the first window's owning application.
    private func loadAppInfo() {
        guard let firstWindow = controller.windows.first else { return }
        guard let app = NSRunningApplication(processIdentifier: firstWindow.pid) else { return }

        appName = app.localizedName ?? "Unknown"
        appIcon = app.icon
    }
}
