import CryptoKit
import Foundation
import LocalAuthentication

enum DeviceKeyKind {
    /// Proves the request comes from the bound device; used with the PIN.
    case device
    /// Gated by Face ID (`biometryCurrentSet`): enrolling a new face invalidates it.
    case biometric
}

protocol DeviceKeyManaging {
    /// Creates (or replaces) a key and returns its public key as X9.63 for the backend.
    func createKey(_ kind: DeviceKeyKind) throws -> Data
    func hasKey(_ kind: DeviceKeyKind) -> Bool
    /// DER ECDSA-SHA256 signature. The biometric key shows the Face ID prompt.
    func sign(_ message: Data, with kind: DeviceKeyKind, reason: String) async throws -> Data
    func deleteKey(_ kind: DeviceKeyKind)
}

enum DeviceKeyError: Error {
    case missingKey
    case biometryUnavailable
    case cancelled
}

/// P-256 keys in the Secure Enclave (spec 13.1 A08, M10). The simulator has no Secure Enclave,
/// so it falls back to a software key kept in the Keychain and a separate Face ID check.
final class SecureEnclaveKeyManager: DeviceKeyManaging {
    private let storage: SecureStorage

    init(storage: SecureStorage) {
        self.storage = storage
    }

    func createKey(_ kind: DeviceKeyKind) throws -> Data {
        if SecureEnclave.isAvailable {
            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: try accessControl(kind))
            try storage.set(key.dataRepresentation, for: storageKey(kind))
            return key.publicKey.x963Representation
        }
        let key = P256.Signing.PrivateKey()
        try storage.set(key.rawRepresentation, for: storageKey(kind))
        return key.publicKey.x963Representation
    }

    func hasKey(_ kind: DeviceKeyKind) -> Bool {
        storage.data(for: storageKey(kind)) != nil
    }

    func sign(_ message: Data, with kind: DeviceKeyKind, reason: String) async throws -> Data {
        guard let stored = storage.data(for: storageKey(kind)) else { throw DeviceKeyError.missingKey }
        let context = LAContext()
        context.localizedReason = reason

        if SecureEnclave.isAvailable {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored, authenticationContext: context)
            do {
                return try key.signature(for: message).derRepresentation
            } catch {
                throw kind == .biometric ? DeviceKeyError.cancelled : error
            }
        }
        if kind == .biometric {
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            } catch {
                throw DeviceKeyError.cancelled
            }
        }
        return try P256.Signing.PrivateKey(rawRepresentation: stored).signature(for: message).derRepresentation
    }

    func deleteKey(_ kind: DeviceKeyKind) {
        storage.remove(storageKey(kind))
    }

    private func accessControl(_ kind: DeviceKeyKind) throws -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if kind == .biometric { flags.insert(.biometryCurrentSet) }
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? DeviceKeyError.biometryUnavailable
        }
        return control
    }

    private func storageKey(_ kind: DeviceKeyKind) -> String {
        kind == .device ? "key.device" : "key.biometric"
    }
}
