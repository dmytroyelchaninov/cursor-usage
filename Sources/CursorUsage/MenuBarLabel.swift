import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.menuBarSymbolName)
            Text(store.menuBarText)
                .monospacedDigit()
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let usage = store.snapshot?.usage {
            return "Cursor models \(Int(usage.autoPercentUsed)) percent, API \(Int(usage.apiPercentUsed)) percent"
        }
        return "Cursor usage unavailable"
    }
}
