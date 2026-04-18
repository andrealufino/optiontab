//
//  optiontabApp.swift
//  optiontab
//
//  Created by Andrea Mario Lufino on 18/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import AppKit
import SwiftUI


/// Application entry point.
///
/// Uses `.accessory` activation policy so OptionTab lives only in the menu bar
/// with no Dock icon. All lifecycle logic is delegated to `AppDelegate`.
@main
struct OptionTabApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: Body

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
