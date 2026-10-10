import Foundation

/// Basic jailbreak signals (AUTH-11). A determined attacker can hide these, so the backend
/// never trusts the result; it only lets the app warn the customer and limit transactions.
enum JailbreakDetector {
    static var isLikelyJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = [
            "/Applications/Cydia.app", "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/",
        ]
        if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        let probe = "/private/luxebank-jb-check.txt"
        if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probe)
            return true
        }
        return false
        #endif
    }
}
