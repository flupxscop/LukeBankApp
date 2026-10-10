import SwiftUI

/// S06 — unlock with PIN or Face ID (AUTH-04, AUTH-05).
struct LockView: View {
    let session: SessionManager
    @State private var pin = ""
    @State private var error: LocalizedStringResource?
    @State private var isError = false
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 30)
            Circle()
                .fill(AngularGradient(colors: [BankTheme.glow, .white, Color(hex: 0xB7BDC9), BankTheme.glow], center: .center))
                .frame(width: 72, height: 72)
                .overlay {
                    Circle().fill(.white).padding(3)
                    Text(String(session.customerFirstName?.prefix(1) ?? "L")).font(BankFont.title(26))
                }
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                if let name = session.customerFirstName {
                    Text("lock.greeting \(name)").font(BankFont.body(15)).foregroundStyle(BankTheme.secondaryText)
                }
                Text("lock.title").font(BankFont.title(22)).accessibilityIdentifier("lock.title")
            }
            PinDots(filled: pin.count, isError: isError)
            Group {
                if let error {
                    InlineError(message: error)
                } else {
                    Text("lock.autoLock").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            .frame(minHeight: 20)
            Spacer()
            if isWorking { ProgressView() }
            PinPad(onDigit: append, onDelete: delete) {
                if session.isBiometricEnabled {
                    Button { Task { await unlockWithBiometric() } } label: {
                        Image(systemName: "faceid")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(BankTheme.ink, in: Circle())
                    }
                    .accessibilityLabel(Text("lock.faceid"))
                } else {
                    Color.clear
                }
            }
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.bottom, 16)
        .background(BankBackground())
        .task {
            if session.isBiometricEnabled { await unlockWithBiometric() }
        }
    }

    private func append(_ digit: Int) {
        guard pin.count < 6, !isWorking else { return }
        isError = false
        error = nil
        pin.append(String(digit))
        if pin.count == 6 { Task { await unlockWithPIN() } }
    }

    private func delete() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func unlockWithPIN() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.unlock(pin: pin)
        } catch {
            self.error = AuthErrorMessage.message(for: error)
            isError = true
        }
        pin = ""
    }

    private func unlockWithBiometric() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.unlockWithBiometric()
        } catch DeviceKeyError.cancelled {
            // The customer chose to type the PIN instead.
        } catch {
            self.error = AuthErrorMessage.message(for: error)
        }
    }
}
