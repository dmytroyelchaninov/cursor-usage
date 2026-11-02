import SwiftUI
import AppKit

@main
struct CursorUsageApp: App {
    @StateObject private var store = UsageStore()

    init() {
        // Menu-bar only — hide Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
