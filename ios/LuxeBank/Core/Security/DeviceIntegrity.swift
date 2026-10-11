import Darwin
import Foundation

/// AUTH-11: whether this phone looks compromised (jailbreak, or a debugger attached to a Release build).
/// Checked once per launch. The backend refuses money movement and card reveals when told so; it can
/// never rely on the app saying "fine", so this protects honest customers, not against attackers.
protocol DeviceIntegrityChecking {
    var isCompromised: Bool { get }
}

struct SystemDeviceIntegrity: DeviceIntegrityChecking {
    let isCompromised: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        // Xcode attaches a debugger to every Debug run; UI tests simulate a compromised phone instead.
        isCompromised = arguments.contains("-SimulateCompromisedDevice") || JailbreakDetector.isLikelyJailbroken
        #else
        isCompromised = JailbreakDetector.isLikelyJailbroken || Self.isDebuggerAttached
        #endif
    }

    /// `P_TRACED` is set while a debugger is attached to this process.
    static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
