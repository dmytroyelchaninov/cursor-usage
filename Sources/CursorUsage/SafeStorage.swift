import Foundation
import CCommonCrypto

/// Decrypts Electron/Chromium `safeStorage` payloads used by Cursor
/// (`cursor-safe-storage:v1:` + base64 of `v10` + AES-128-CBC ciphertext).
enum SafeStorage {
    private static let sealedPrefix = "cursor-safe-storage:v1:"
    private static let v10Prefix = Data("v10".utf8)

    static func decrypt(sealedValue: String, keychainPassword: String) throws -> String {
        guard sealedValue.hasPrefix(sealedPrefix) else {
            throw UsageError.decryptFailed
        }
        let b64 = String(sealedValue.dropFirst(sealedPrefix.count))
        guard let blob = Data(base64Encoded: b64), blob.starts(with: v10Prefix) else {
            throw UsageError.decryptFailed
        }

        let ciphertext = blob.dropFirst(v10Prefix.count)
        let key = pbkdf2(password: Data(keychainPassword.utf8))
        let iv = Data(repeating: 0x20, count: 16) // 16 spaces
        let plain = try aes128CBCDecrypt(data: Data(ciphertext), key: key, iv: iv)
        guard let token = String(data: plain, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw UsageError.decryptFailed
        }
        return token
    }

    private static func pbkdf2(password: Data) -> Data {
        var derived = Data(count: 16)
        let salt = Data("saltysalt".utf8)
        let passwordCount = password.count
        let saltCount = salt.count
        _ = derived.withUnsafeMutableBytes { derivedBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordCount,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltCount,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        16
                    )
                }
            }
        }
        return derived
    }

    private static func aes128CBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var outLength = 0
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        let dataCount = data.count
        let keyCount = key.count
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyCount,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, dataCount,
                            outBytes.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw UsageError.decryptFailed }
        return out.prefix(outLength)
    }
}
