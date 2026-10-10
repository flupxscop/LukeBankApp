import LocalAuthentication

protocol BiometricAvailability {
    /// True when Face ID / Touch ID is set up on this iPhone.
    var isAvailable: Bool { get }
}

struct SystemBiometrics: BiometricAvailability {
    var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
