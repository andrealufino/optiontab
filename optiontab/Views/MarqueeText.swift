//
//  MarqueeText.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import SwiftUI


/// A text view that scrolls its content horizontally when it overflows the available width.
///
/// The animation pauses briefly at the start, scrolls to the end at a constant pace,
/// then resets and repeats. No scrolling occurs when the text fits within the container.
struct MarqueeText: View {

    // MARK: State & Environment

    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false


    // MARK: Computed Properties

    /// Whether the text overflows its container and scrolling is needed.
    private var shouldScroll: Bool {
        textWidth > containerWidth
    }

    /// The total scroll distance required.
    private var scrollDistance: CGFloat {
        max(0, textWidth - containerWidth)
    }


    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .offset(x: -offset)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeo.size.width
                                    containerWidth = geometry.size.width
                                    startAnimationIfNeeded()
                                }
                                .onChange(of: text) {
                                    offset = 0
                                    isAnimating = false
                                    textWidth = textGeo.size.width
                                    startAnimationIfNeeded()
                                }
                        }
                    )
            }
            .clipped()
            .onChange(of: geometry.size.width) { _, newWidth in
                containerWidth = newWidth
                if !shouldScroll {
                    offset = 0
                    isAnimating = false
                }
            }
        }
    }


    // MARK: Private Methods

    /// Starts the scrolling animation loop when the text overflows.
    private func startAnimationIfNeeded() {
        guard shouldScroll, !isAnimating else { return }
        isAnimating = true
        animateLoop()
    }

    /// Runs one full scroll cycle: pause → scroll → reset → repeat.
    private func animateLoop() {
        guard shouldScroll else {
            isAnimating = false
            offset = 0
            return
        }

        // Pause at start for 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let duration = Double(scrollDistance) / 50 // ~50 pts/second
            withAnimation(.linear(duration: duration)) {
                offset = scrollDistance
            }
            // After scrolling, pause briefly then reset
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.8) {
                offset = 0
                animateLoop()
            }
        }
    }
}
