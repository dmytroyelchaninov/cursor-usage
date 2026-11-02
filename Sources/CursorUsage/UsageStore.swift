import Foundation
import AppKit
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var authStatus: AuthStatus = .loggedOut
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published var refreshIntervalSeconds: TimeInterval = 60

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init() {
        startPolling()
        Task { await refresh() }
    }

    deinit {
        timer?.invalidate()
    }

    var menuBarText: String {
        if let usage = snapshot?.usage {
            let models = Int(min(999, usage.autoPercentUsed.rounded()))
            let api = Int(min(999, usage.apiPercentUsed.rounded()))
            return "\(models)·\(api)"
        }
        switch authStatus {
        case .loggedOut, .needsCursorLogin:
            return "–"
        case .keychainDenied:
            return "!"
        case .loggedIn:
            return "…"
        }
    }

    var menuBarSymbolName: String {
        guard let usage = snapshot?.usage else {
            return "circle.dashed"
        }
        let peak = max(usage.autoPercentUsed, usage.apiPercentUsed)
        if peak >= 100 { return "exclamationmark.circle.fill" }
        if peak >= 80 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh() async {
        refreshTask?.cancel()
        let task = Task { @MainActor in
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        isLoading = true
        defer { isLoading = false }

        let profile = AuthStore.loadCachedProfile()

        do {
            try await fetchWithToken(
                accessToken: try AuthStore.loadAccessToken(),
                email: profile.email,
                membership: profile.membership
            )
        } catch UsageError.notLoggedIn {
            // Cached session may be stale — pull once from Cursor and retry.
            do {
                AuthStore.invalidateCache()
                try await fetchWithToken(
                    accessToken: try AuthStore.loadAccessToken(forceReloadFromCursor: true),
                    email: profile.email,
                    membership: profile.membership
                )
            } catch {
                handleRefreshFailure(error)
            }
        } catch {
            handleRefreshFailure(error)
        }
    }

    private func fetchWithToken(accessToken: String, email: String?, membership: String?) async throws {
        authStatus = .loggedIn(email: email)
        let snap = try await UsageClient.fetchSnapshot(
            accessToken: accessToken,
            email: email,
            membership: membership
        )
        snapshot = snap
        lastError = nil
    }

    private func handleRefreshFailure(_ error: Error) {
        lastError = error.localizedDescription
        if let error = error as? UsageError {
            switch error {
            case .notLoggedIn:
                authStatus = AuthStore.isCursorInstalled() ? .needsCursorLogin : .loggedOut
                snapshot = nil
            case .keychainDenied:
                authStatus = .keychainDenied
            default:
                if snapshot == nil {
                    authStatus = .needsCursorLogin
                }
            }
        } else if snapshot == nil {
            authStatus = .needsCursorLogin
        }
    }

    func openCursorApp() {
        let url = URL(fileURLWithPath: "/Applications/Cursor.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            openDashboard()
        }
    }

    func openDashboard() {
        if let url = URL(string: "https://cursor.com/dashboard") {
            NSWorkspace.shared.open(url)
        }
    }

    func openUsagePage() {
        if let url = URL(string: "https://cursor.com/dashboard/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
