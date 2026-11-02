import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject private var store: UsageStore
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            quitButton
        }
        .padding(12)
        .frame(width: 260)
        .onDisappear {
            showDetails = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cursor Usage")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .opacity(store.isLoading ? 0.4 : 1)
            .help("Refresh")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.authStatus {
        case .loggedOut, .needsCursorLogin:
            loginPrompt
        case .keychainDenied:
            keychainPrompt
        case .loggedIn:
            if let usage = store.snapshot?.usage {
                usageDetails(usage)
            } else if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                loginPrompt
            }
        }
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Cursor on this Mac, then refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button("Open Cursor") { store.openCursorApp() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Dashboard") { store.openDashboard() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var keychainPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow Keychain once")
                .font(.caption.weight(.semibold))
            Text("macOS will ask for “Cursor Safe Storage”. Choose Always Allow — we cache the session so it won’t ask again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await store.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func usageDetails(_ usage: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            usageLine(title: "Cursor", percent: usage.autoPercentUsed)
            usageLine(title: "API", percent: usage.apiPercentUsed)

            HStack(spacing: 6) {
                Text(shortMeta)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)

                Spacer(minLength: 4)

                Button(showDetails ? "Hide" : "Details") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetails.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.medium))

                Button {
                    store.openUsagePage()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Open on cursor.com")
            }
            .padding(.top, 2)

            if showDetails {
                expandedDetails(usage)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func expandedDetails(_ usage: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Plan", planLabel)
            detailRow(
                "Included",
                String(format: "$%.2f / $%.2f", usage.includedSpendDollars, usage.limitDollars)
            )
            if usage.bonusSpendCents > 0 {
                detailRow("Bonus", String(format: "$%.2f", usage.bonusSpendDollars))
            }
            detailRow("Total spend", String(format: "$%.2f", usage.totalSpendDollars))
            detailRow("Total used", String(format: "%.0f%%", usage.totalPercentUsed))

            if let message = usage.autoDisplayMessage
                ?? usage.namedDisplayMessage
                ?? usage.displayMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if let fetched = store.snapshot?.fetchedAt {
                Text("Updated \(fetched.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func usageLine(title: String, percent: Double) -> some View {
        let clamped = min(max(percent, 0), 100)
        let color: Color = percent >= 100 ? .red : percent >= 80 ? .orange : .primary

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: geo.size.width * (clamped / 100.0))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var quitButton: some View {
        Button {
            store.quit()
        } label: {
            Text("Quit")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var shortMeta: String {
        let name = store.snapshot?.plan?.planName
            ?? store.snapshot?.membershipType?.capitalized
            ?? "Cursor"
        if let end = store.snapshot?.usage?.billingCycleEnd
            ?? store.snapshot?.plan?.billingCycleEnd {
            return "\(name) · resets \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return name
    }

    private var planLabel: String {
        let name = store.snapshot?.plan?.planName
            ?? store.snapshot?.membershipType?.capitalized
            ?? "—"
        let price = store.snapshot?.plan?.price ?? ""
        if price.isEmpty { return name }
        return "\(name) · \(price)"
    }
}
