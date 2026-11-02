import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Interval", selection: $store.refreshIntervalSeconds) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                .onChange(of: store.refreshIntervalSeconds) { _, _ in
                    store.startPolling()
                }
            }

            Section("About") {
                Text("Uses your local Cursor login (no separate account). Usage comes from Cursor’s undocumented dashboard API and may change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 220)
    }
}
