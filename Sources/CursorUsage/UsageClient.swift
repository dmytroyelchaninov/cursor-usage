import Foundation

enum UsageClient {
    private static let baseURL = URL(string: "https://api2.cursor.sh")!

    static func fetchSnapshot(accessToken: String, email: String?, membership: String?) async throws -> UsageSnapshot {
        async let usage = getCurrentPeriodUsage(accessToken: accessToken)
        async let plan = getPlanInfo(accessToken: accessToken)

        let (usageValue, planValue) = try await (usage, plan)
        return UsageSnapshot(
            email: email,
            membershipType: membership ?? planValue.planName.lowercased(),
            plan: planValue,
            usage: usageValue,
            fetchedAt: Date()
        )
    }

    private static func getCurrentPeriodUsage(accessToken: String) async throws -> PeriodUsage {
        let data = try await post(
            path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            accessToken: accessToken,
            body: Data("{}".utf8)
        )
        return try decodePeriodUsage(data)
    }

    private static func getPlanInfo(accessToken: String) async throws -> PlanInfo {
        let data = try await post(
            path: "/aiserver.v1.DashboardService/GetPlanInfo",
            accessToken: accessToken,
            body: Data("{}".utf8)
        )
        return try decodePlanInfo(data)
    }

    private static func post(path: String, accessToken: String, body: Data) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw UsageError.unexpected("Bad URL path")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("No HTTP response")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageError.notLoggedIn
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            // Connect protocol may return 200 with code field; also handle JSON error bodies
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = obj["code"] as? String,
               code == "unauthenticated" {
                throw UsageError.notLoggedIn
            }
            throw UsageError.network(message)
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["code"] as? String,
           code == "unauthenticated" {
            throw UsageError.notLoggedIn
        }

        return data
    }

    // MARK: - Decoding (tolerant of evolving undocumented shapes)

    private static func decodePlanInfo(_ data: Data) throws -> PlanInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["planInfo"] as? [String: Any] else {
            throw UsageError.decode("planInfo")
        }
        return PlanInfo(
            planName: info["planName"] as? String ?? "Cursor",
            price: info["price"] as? String ?? "",
            billingCycleEnd: date(from: info["billingCycleEnd"])
        )
    }

    private static func decodePeriodUsage(_ data: Data) throws -> PeriodUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.decode("root")
        }
        let plan = root["planUsage"] as? [String: Any] ?? [:]

        return PeriodUsage(
            billingCycleStart: date(from: root["billingCycleStart"]),
            billingCycleEnd: date(from: root["billingCycleEnd"]),
            totalSpendCents: intValue(plan["totalSpend"]),
            includedSpendCents: intValue(plan["includedSpend"]),
            bonusSpendCents: intValue(plan["bonusSpend"]),
            limitCents: intValue(plan["limit"]),
            autoPercentUsed: doubleValue(plan["autoPercentUsed"]),
            apiPercentUsed: doubleValue(plan["apiPercentUsed"]),
            totalPercentUsed: doubleValue(plan["totalPercentUsed"]),
            displayMessage: root["displayMessage"] as? String,
            autoDisplayMessage: root["autoModelSelectedDisplayMessage"] as? String,
            namedDisplayMessage: root["namedModelSelectedDisplayMessage"] as? String,
            enabled: (root["enabled"] as? Bool) ?? true
        )
    }

    private static func date(from value: Any?) -> Date? {
        if let n = value as? NSNumber {
            // epoch ms
            let v = n.doubleValue
            return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000.0 : v)
        }
        if let s = value as? String {
            if let n = Double(s) {
                return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000.0 : n)
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: s)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        if let d = value as? Double { return Int(d) }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        if let i = value as? Int { return Double(i) }
        return 0
    }
}
