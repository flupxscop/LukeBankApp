import CryptoKit
import Foundation
import Security
import Testing
@testable import LuxeBank

/// Spec 13.4.4: the app refuses a server whose key is not pinned.
struct PinningTests {
    private func makeKey() throws -> (SecKey, P256.Signing.PublicKey) {
        let privateKey = P256.Signing.PrivateKey()
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        let key = try #require(SecKeyCreateWithData(privateKey.publicKey.x963Representation as CFData, attributes as CFDictionary, nil))
        return (key, privateKey.publicKey)
    }

    @Test func hashIsSHA256OfTheSubjectPublicKeyInfo() throws {
        let (key, publicKey) = try makeKey()
        // CryptoKit's DER form is the SubjectPublicKeyInfo, the same bytes OkHttp and HPKP pins hash.
        let expected = Data(SHA256.hash(data: publicKey.derRepresentation)).base64EncodedString()
        #expect(PinnedSessionDelegate.spkiHash(of: key) == expected)
    }

    @Test func onlyAPinnedKeyIsAccepted() throws {
        let (server, _) = try makeKey()
        let (backup, _) = try makeKey()
        let serverPin = try #require(PinnedSessionDelegate.spkiHash(of: server))
        let backupPin = try #require(PinnedSessionDelegate.spkiHash(of: backup))

        #expect(PinnedSessionDelegate.matches(keys: [server], pins: [serverPin, backupPin]))
        #expect(PinnedSessionDelegate.matches(keys: [backup], pins: [serverPin, backupPin]))
        let (attacker, _) = try makeKey()
        #expect(!PinnedSessionDelegate.matches(keys: [attacker], pins: [serverPin, backupPin]))
        #expect(!PinnedSessionDelegate.matches(keys: [], pins: [serverPin]))
    }
}
