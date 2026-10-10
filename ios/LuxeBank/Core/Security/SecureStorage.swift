import Foundation
import Security

/// Small secrets and identifiers that must not leave the device (spec 13.1 M9).
protocol SecureStorage: AnyObject {
    func data(for key: String) -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String)
}

extension SecureStorage {
    func string(for key: String) -> String? {
        data(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    func set(_ string: String, for key: String) throws {
        try set(Data(string.utf8), for: key)
    }
}

enum SecureStorageError: Error {
    case unexpectedStatus(OSStatus)
}

/// Keychain items readable only while unlocked, never synced or restored to another device.
final class KeychainStore: SecureStorage {
    private let service: String

    init(service: String = "com.luxebank.app") {
        self.service = service
    }

    func data(for key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, for key: String) throws {
        remove(key)
        var query = baseQuery(key)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureStorageError.unexpectedStatus(status) }
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }
}

/// For previews and tests.
final class InMemorySecureStorage: SecureStorage {
    private var values: [String: Data] = [:]

    func data(for key: String) -> Data? { values[key] }
    func set(_ data: Data, for key: String) throws { values[key] = data }
    func remove(_ key: String) { values[key] = nil }
}
