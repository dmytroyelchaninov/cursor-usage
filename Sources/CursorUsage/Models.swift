import Foundation

struct PlanInfo: Equatable {
    var planName: String
    var price: String
    var billingCycleEnd: Date?
}

struct PeriodUsage: Equatable {
    var billingCycleStart: Date?
    var billingCycleEnd: Date?
    var totalSpendCents: Int
    var includedSpendCents: Int
    var bonusSpendCents: Int
    var limitCents: Int
    var autoPercentUsed: Double
    var apiPercentUsed: Double
    var totalPercentUsed: Double
    var displayMessage: String?
    var autoDisplayMessage: String?
    var namedDisplayMessage: String?
    var enabled: Bool

    var limitDollars: Double { Double(limitCents) / 100.0 }
    var totalSpendDollars: Double { Double(totalSpendCents) / 100.0 }
    var includedSpendDollars: Double { Double(includedSpendCents) / 100.0 }
    var bonusSpendDollars: Double { Double(bonusSpendCents) / 100.0 }

    /// Primary gauge: total plan percent used (matches Cursor UI).
    var percentUsed: Double { totalPercentUsed }

    var remainingIncludedDollars: Double {
        max(0, Double(limitCents - includedSpendCents) / 100.0)
    }
}

struct UsageSnapshot: Equatable {
    var email: String?
    var membershipType: String?
    var plan: PlanInfo?
    var usage: PeriodUsage?
    var fetchedAt: Date
}

enum AuthStatus: Equatable {
    case loggedOut
    case loggedIn(email: String?)
    case needsCursorLogin
    case keychainDenied
}

enum UsageError: LocalizedError, Equatable {
    case notLoggedIn
    case keychainDenied
    case decryptFailed
    case network(String)
    case decode(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Cursor is not signed in on this Mac."
        case .keychainDenied:
            return "Allow Keychain access to “Cursor Safe Storage” once (Always Allow)."
        case .decryptFailed:
            return "Could not decrypt Cursor’s saved login."
        case .network(let message):
            return message
        case .decode(let message):
            return "Unexpected response: \(message)"
        case .unexpected(let message):
            return message
        }
    }
}
