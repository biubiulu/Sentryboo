import CryptoKit
import Foundation
import Security

struct TokenStore: Sendable {
    private let service = "app.sentryboo.Sentryboo"
    private let legacyAccount = "zabbix.apiToken"
    private let fileName = "zabbix-tokens.json.enc"
    private let salt = "sentryboo.token.v1"

    func saveToken(_ token: String, accountID: UUID) throws {
        var map = loadTokenMap()
        map[accountID.uuidString] = token
        try persistTokenMap(map)
        try? deleteKeychainAccount(tokenAccount(for: accountID))
    }

    func readToken(accountID: UUID) throws -> String? {
        let value = loadTokenMap()[accountID.uuidString]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    func deleteToken(accountID: UUID) throws {
        var map = loadTokenMap()
        map.removeValue(forKey: accountID.uuidString)
        try persistTokenMap(map)
        try? deleteKeychainAccount(tokenAccount(for: accountID))
    }

    /// 从旧 Keychain 槽位迁入加密文件，成功后删除钥匙串项。
    func migrateFromKeychainIfNeeded(accountIDs: [UUID]) {
        guard !accountIDs.isEmpty else { return }

        var map = loadTokenMap()
        var changed = false
        var deletableKeychainAccounts: [String] = []

        for accountID in accountIDs {
            let key = accountID.uuidString
            let slotted = tokenAccount(for: accountID)
            if let existing = map[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !existing.isEmpty {
                // 文件已有 Token，清理对应钥匙串残留即可。
                deletableKeychainAccounts.append(slotted)
                continue
            }
            if let token = try? readKeychain(account: slotted)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty {
                map[key] = token
                changed = true
                deletableKeychainAccounts.append(slotted)
            }
        }

        var legacyMigrated = false
        if let legacy = try? readKeychain(account: legacyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            if let missingID = accountIDs.first(where: { id in
                let value = map[id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty
            }) {
                map[missingID.uuidString] = legacy
                changed = true
                legacyMigrated = true
            } else {
                // 所有账号已有 Token，legacy 可安全清理。
                legacyMigrated = true
            }
        }

        if changed {
            do {
                try persistTokenMap(map)
            } catch {
                logDebug("Token 文件迁移写入失败：\(error.localizedDescription)")
                return
            }
        }

        for account in Set(deletableKeychainAccounts) {
            try? deleteKeychainAccount(account)
        }
        if legacyMigrated {
            try? deleteKeychainAccount(legacyAccount)
        }
    }

    // MARK: - File store

    private struct TokenFilePayload: Codable {
        var version: Int
        var tokens: [String: String]
    }

    private func loadTokenMap() -> [String: String] {
        let url = tokenFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let plain = try decrypt(data)
            let payload = try JSONDecoder().decode(TokenFilePayload.self, from: plain)
            return payload.tokens
        } catch {
            logDebug("Token 文件读取失败，按空表处理：\(error.localizedDescription)")
            return [:]
        }
    }

    private func logDebug(_ message: String) {
        Task { @MainActor in
            DebugLog.shared.append(message)
        }
    }

    private func persistTokenMap(_ tokens: [String: String]) throws {
        let payload = TokenFilePayload(version: 1, tokens: tokens)
        let plain = try JSONEncoder().encode(payload)
        let encrypted = try encrypt(plain)
        let url = tokenFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encrypted.write(to: url, options: [.atomic])
    }

    private func tokenFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root
            .appendingPathComponent(service, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - Crypto

    private func symmetricKey() -> SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? service
        let material = Data((salt + "|" + bundleID).utf8)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    private func encrypt(_ plain: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: symmetricKey())
        guard let combined = sealed.combined else {
            throw TokenStoreError.cryptoFailed
        }
        return combined
    }

    private func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: symmetricKey())
    }

    // MARK: - Legacy Keychain helpers (migration / cleanup only)

    private func tokenAccount(for accountID: UUID) -> String {
        "zabbix.apiToken.\(accountID.uuidString)"
    }

    private func readKeychain(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TokenStoreError.keychainFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainAccount(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainFailed(status)
        }
    }
}

enum TokenStoreError: LocalizedError {
    case cryptoFailed
    case keychainFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .cryptoFailed:
            return "Token 加密失败。"
        case .keychainFailed(let status):
            return "钥匙串清理失败（\(status)）。"
        }
    }
}
