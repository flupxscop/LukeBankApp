import CryptoKit
import Foundation

/// Public-key pinning (spec 13.1 M5). Pins are base64 SHA-256 hashes of the server's
/// SubjectPublicKeyInfo; ship at least one backup pin. Empty pins disable pinning (local dev only).
final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
    private let pins: Set<String>

    init(pins: Set<String>) {
        self.pins = pins
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard !pins.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let matches = chain.contains { certificate in
            guard let key = SecCertificateCopyKey(certificate), let hash = Self.spkiHash(of: key) else { return false }
            return pins.contains(hash)
        }
        completionHandler(matches ? .useCredential : .cancelAuthenticationChallenge, matches ? URLCredential(trust: trust) : nil)
    }

    /// SHA-256 over the DER SubjectPublicKeyInfo, base64 encoded (same format as HPKP / OkHttp pins).
    static func spkiHash(of key: SecKey) -> String? {
        guard let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attributes[kSecAttrKeyType] as? String,
              let bits = attributes[kSecAttrKeySizeInBits] as? Int,
              let header = spkiHeader(type: type, bits: bits)
        else { return nil }
        return Data(SHA256.hash(data: header + raw)).base64EncodedString()
    }

    private static func spkiHeader(type: String, bits: Int) -> Data? {
        if type == kSecAttrKeyTypeECSECPrimeRandom as String, bits == 256 {
            return Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                         0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00])
        }
        if type == kSecAttrKeyTypeRSA as String, bits == 2048 {
            return Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86,
                         0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00])
        }
        return nil
    }
}
