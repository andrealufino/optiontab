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
/// Renders a vertical Liquid Glass container with one `WindowRowView` per window.
/// Wraps in a `ScrollView` when the list exceeds the available height, and keeps
/// the selected row scrolled into view on every cycle step.
struct SwitcherListView: View {

    // MARK: State & Environment

    let controller: OverlayController

    @State private var appIcon: NSImage? = nil
    @State private var appName: String = ""
    @State private var scrollProxy: ScrollViewProxy? = nil


    // MARK: Body

    var body: some View {
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
                                controller.confirmSelection(tappedWindow)
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
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
