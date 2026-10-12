import SwiftUI

/// S02 → S05 in one navigation stack.
struct RegistrationFlowView: View {
    @State var viewModel: RegistrationViewModel
    let onCancel: () -> Void

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            CredentialsView(viewModel: viewModel, onBack: onCancel)
                .navigationDestination(for: RegistrationViewModel.Step.self) { step in
                    switch step {
                    case .otp: OTPView(viewModel: viewModel)
                    case .pin: PinSetupView(viewModel: viewModel)
                    case .biometric: BiometricOptInView(viewModel: viewModel)
                    }
                }
        }
    }
}

// MARK: - S02 Credentials

private struct CredentialsView: View {
    @Bindable var viewModel: RegistrationViewModel
    let onBack: () -> Void
    @FocusState private var isPasswordFocused: Bool
    @State private var isCitizenIDFocused = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                OnboardingHeader(step: 1, onBack: onBack)
                VStack(alignment: .leading, spacing: 10) {
                    Text("register.title").font(BankFont.title(32))
                    Text("register.subtitle").font(BankFont.body(15)).foregroundStyle(BankTheme.secondaryText)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 18) {
                    field(title: "register.citizenID", isFocused: isCitizenIDFocused, isValid: viewModel.isCitizenIDValid) {
                        FormattedDigitsField(
                            digits: $viewModel.citizenIDDigits,
                            maxDigits: 13,
                            placeholder: "X-XXXX-XXXXX-XX-X",
                            format: CitizenID.formatted,
                            isFocused: $isCitizenIDFocused,
                            accessibilityIdentifier: "register.citizenID"
                        )
                        .frame(minHeight: 44)
                    }
                    field(title: "register.password", isFocused: isPasswordFocused, isValid: false) {
                        SecureField("", text: $viewModel.password)
                            .textContentType(.password)
                            .focused($isPasswordFocused)
                            .accessibilityIdentifier("register.password")
                            .submitLabel(.go)
                            .onSubmit { Task { await viewModel.submitCredentials() } }
                    }
                    InlineError(message: viewModel.error)
                }
                .surfaceCard(padding: 20)

                Label { Text("register.binding") } icon: { Image(systemName: "lock") }
                    .font(BankFont.caption(13))
                    .foregroundStyle(Color(hex: 0x24427F))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BankTheme.accentTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await viewModel.submitCredentials() }
            } label: {
                if viewModel.isLoading { ProgressView().tint(.white) } else { Text("register.requestOTP") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canSubmitCredentials)
            .accessibilityIdentifier("register.submit")
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 10)
        }
        .background(BankBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Focus after the push transition; setting it in onAppear is ignored mid-animation.
            try? await Task.sleep(for: .milliseconds(450))
            isCitizenIDFocused = true
        }
    }

    private func field<Content: View>(
        title: LocalizedStringKey,
        isFocused: Bool,
        isValid: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(isFocused ? BankTheme.accent : Color(hex: 0x3A404C))
            HStack {
                content().font(BankFont.body(17, bold: true))
                if isValid {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BankTheme.positive)
                        .accessibilityLabel(Text("register.citizenID.valid"))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(isFocused ? BankTheme.surface : BankTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: BankTheme.Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BankTheme.Radius.field, style: .continuous)
                    .stroke(isFocused ? BankTheme.accent : BankTheme.lineStrong, lineWidth: isFocused ? 1.5 : 1)
            )
        }
    }
}

// MARK: - S03 OTP

private struct OTPView: View {
    @Bindable var viewModel: RegistrationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(step: 2) { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text("otp.title").font(BankFont.title(32))
                Text("otp.subtitle \(viewModel.challenge?.maskedPhone ?? "")")
                    .font(BankFont.body(15))
                    .foregroundStyle(BankTheme.secondaryText)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(viewModel.otpCode)
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(BankFont.figure(28))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(index == digits.count ? BankTheme.accent : .clear, lineWidth: 1.5)
                        )
                        .cardShadow(radius: 16, y: 6, opacity: 0.07)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("otp.progress \(viewModel.otpCode.count)"))
            .accessibilityIdentifier("otp.progress")

            HStack {
                Text("otp.reference \(viewModel.challenge?.otpRef ?? "")")
                Spacer()
                if let availableAt = viewModel.resendAvailableAt {
                    Text(timerInterval: Date()...max(Date(), availableAt), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(BankTheme.accent)
                }
            }
            .font(BankFont.caption(13))
            .foregroundStyle(BankTheme.secondaryText)
            .padding(.horizontal, 4)

            InlineError(message: viewModel.error).frame(maxWidth: .infinity)
            Spacer()
            if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity) }
            PinPad(onDigit: { digit in Task { await viewModel.appendOTPDigit(digit) } }, onDelete: viewModel.deleteOTPDigit)
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 12)
        .background(BankBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - S04 PIN

private struct PinSetupView: View {
    @Bindable var viewModel: RegistrationViewModel

    var body: some View {
        VStack(spacing: 24) {
            OnboardingHeader(step: 3)
            VStack(spacing: 8) {
                Text(viewModel.isConfirmingPin ? "pin.confirm.title" : "pin.setup.title").font(BankFont.title(28))
                Text("pin.setup.subtitle").font(BankFont.body(15)).foregroundStyle(BankTheme.secondaryText)
            }
            PinDots(filled: viewModel.pin.count)
            if !viewModel.isConfirmingPin {
                HStack(spacing: 8) {
                    ruleChip("pin.rule.sequence", passed: viewModel.pinRules.notSequential)
                    ruleChip("pin.rule.repeat", passed: viewModel.pinRules.notRepeated)
                }
            }
            InlineError(message: viewModel.error)
            Spacer()
            if viewModel.isLoading { ProgressView() }
            PinPad(onDigit: { digit in Task { await viewModel.appendPinDigit(digit) } }, onDelete: viewModel.deletePinDigit)
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 12)
        .background(BankBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    private func ruleChip(_ title: LocalizedStringKey, passed: Bool) -> some View {
        Label { Text(title) } icon: { Image(systemName: passed ? "checkmark" : "circle") }
            .font(BankFont.caption(12, bold: true))
            .foregroundStyle(passed ? BankTheme.positive : BankTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(passed ? BankTheme.positiveTint : BankTheme.surface, in: Capsule())
    }
}

// MARK: - S05 Face ID

private struct BiometricOptInView: View {
    @Bindable var viewModel: RegistrationViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 40)
            Image(systemName: "faceid")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(BankTheme.accent)
                .frame(width: 128, height: 128)
                .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                .cardShadow(radius: 60, y: 30, opacity: 0.22)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("faceid.title").font(BankFont.title(30))
                Text("faceid.subtitle").font(BankFont.body(15)).foregroundStyle(BankTheme.secondaryText).multilineTextAlignment(.center)
            }
            VStack(spacing: 0) {
                benefit("shield", title: "faceid.benefit.local", detail: "faceid.benefit.local.detail")
                Divider().overlay(BankTheme.line)
                benefit("arrow.up.right", title: "faceid.benefit.stepUp", detail: "faceid.benefit.stepUp.detail")
            }
            .surfaceCard(radius: 24, padding: 18)
            InlineError(message: viewModel.error)
            Spacer()
            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.enableBiometric() }
                } label: {
                    if viewModel.isLoading { ProgressView().tint(.white) } else { Text("faceid.enable") }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("faceid.later", action: viewModel.skipBiometric)
                    .accessibilityIdentifier("faceid.later")
                    .font(BankFont.body(15, bold: true))
                    .foregroundStyle(BankTheme.secondaryText)
                    .frame(minHeight: 48)
            }
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 12)
        .background(BankBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    private func benefit(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            IconTile(content: .symbol(symbol), size: 40, tint: BankTheme.accent, fill: BankTheme.accentTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BankFont.body(15, bold: true))
                Text(detail).font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}
