import Foundation
import Security
import SQLite3

enum AuthStore {
    private static let stateDBRelativePath =
        "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    private static let accessTokenKey = "cursorAuth/accessToken"
    private static let emailKey = "cursorAuth/cachedEmail"
    private static let membershipKey = "cursorAuth/stripeMembershipType"
    private static let sealedPrefix = "cursor-safe-storage:v1:"
    private static let keychainService = "Cursor Safe Storage"
    private static let keychainAccount = "Cursor Key"

    /// Our cache — avoids re-touching Cursor’s Keychain on every poll.
    private static let cacheDirRelativePath = "Library/Application Support/CursorUsage"
    private static let cacheFileName = "session.json"
    private static let refreshSkew: TimeInterval = 5 * 60

    private static var memoryToken: String?

    static var stateDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(stateDBRelativePath)
    }

    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(cacheDirRelativePath)
            .appendingPathComponent(cacheFileName)
    }

    static func loadCachedProfile() -> (email: String?, membership: String?) {
        (
            readStateValue(emailKey),
            readStateValue(membershipKey)
        )
    }

    /// Returns a Bearer token. Prefers in-memory / file cache so macOS only
    /// asks for Cursor Safe Storage when we have nothing usable cached.
    static func loadAccessToken(forceReloadFromCursor: Bool = false) throws -> String {
        if !forceReloadFromCursor {
            if let memoryToken, !isExpired(memoryToken) {
                return memoryToken
            }
            if let cached = readCache(), !isExpired(cached) {
                memoryToken = cached
                return cached
            }
        }

        let token = try loadAccessTokenFromCursor()
        memoryToken = token
        writeCache(token)
        return token
    }

    static func invalidateCache() {
        memoryToken = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    static func isCursorInstalled() -> Bool {
        FileManager.default.fileExists(atPath: stateDBURL.path)
            || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
    }

    // MARK: - Cursor decrypt (rare)

    private static func loadAccessTokenFromCursor() throws -> String {
        guard FileManager.default.fileExists(atPath: stateDBURL.path) else {
            throw UsageError.notLoggedIn
        }

        guard let sealedOrPlain = readStateValue(accessTokenKey), !sealedOrPlain.isEmpty else {
            throw UsageError.notLoggedIn
        }

        if sealedOrPlain.hasPrefix(sealedPrefix) {
            let password = try readCursorSafeStoragePassword()
            do {
                return try SafeStorage.decrypt(
                    sealedValue: sealedOrPlain,
                    keychainPassword: password
                )
            } catch {
                throw UsageError.decryptFailed
            }
        }

        return sealedOrPlain
    }

    // MARK: - Session file cache

    private struct SessionCache: Codable {
        var accessToken: String
        var savedAt: Date
    }

    private static func readCache() -> String? {
        guard let data = try? Data(contentsOf: cacheURL),
              let session = try? JSONDecoder().decode(SessionCache.self, from: data),
              !session.accessToken.isEmpty else {
            return nil
        }
        return session.accessToken
    }

    private static func writeCache(_ token: String) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let session = SessionCache(accessToken: token, savedAt: Date())
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: cacheURL.path
        )
    }

    private static func isExpired(_ jwt: String) -> Bool {
        guard let exp = jwtExpiry(jwt) else { return false }
        return Date().addingTimeInterval(refreshSkew) >= exp
    }

    private static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        b64.append(String(repeating: "=", count: pad))
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let exp = obj["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = obj["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    // MARK: - SQLite

    private static func readStateValue(_ key: String) -> String? {
        var db: OpaquePointer?
        let path = stateDBURL.path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let nsKey = key as NSString
        sqlite3_bind_text(statement, 1, nsKey.utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        if let cString = sqlite3_column_text(statement, 0) {
            return String(cString: cString)
        }

        let bytes = sqlite3_column_bytes(statement, 0)
        if bytes > 0, let blob = sqlite3_column_blob(statement, 0) {
            let data = Data(bytes: blob, count: Int(bytes))
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            if let utf16 = String(data: data, encoding: .utf16LittleEndian)?
                .trimmingCharacters(in: .controlCharacters), !utf16.isEmpty {
                return utf16
            }
        }
        return nil
    }

    // MARK: - Keychain (only when cache is cold)

    private static func readCursorSafeStoragePassword() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw UsageError.keychainDenied
        }
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw UsageError.notLoggedIn
        }
        return password
    }
}
