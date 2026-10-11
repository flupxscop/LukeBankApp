import SwiftUI

/// S20 — PIN, Face ID, language, notification preferences, devices and sign-out (PROF-02…06, PROF-08).
struct SettingsView: View {
    @Bindable var viewModel: ProfileViewModel
    let onBack: () -> Void
    @State private var changePin: ChangePinViewModel?
    @State private var isConfirmingLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PushedHeader(title: "settings.title", onBack: onBack)
                security
                language
                notifications
                devices
                InlineError(message: viewModel.error).frame(maxWidth: .infinity)
                logout
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
        .sheet(item: $changePin) { model in
            ChangePinView(viewModel: model) { changePin = nil }
        }
        .confirmationDialog("settings.logout.confirmTitle", isPresented: $isConfirmingLogout, titleVisibility: .visible) {
            Button("settings.logout.confirm", role: .destructive) {
                Task { await viewModel.logout() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.logout.message")
        }
    }

    private var security: some View {
        SettingsSection(title: "settings.security") {
            Button { changePin = viewModel.makeChangePin() } label: {
                SettingsRow(symbol: "circle.grid.3x3", title: "settings.changePin")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.changePin")
            SettingsDivider()
            SettingsRow(symbol: "faceid", title: "settings.faceID", subtitle: viewModel.canUseBiometric ? nil : "settings.faceID.unavailable") {
                Toggle("settings.faceID", isOn: Binding(
                    get: { viewModel.isBiometricEnabled },
                    set: { isOn in Task { await viewModel.setBiometric(isOn) } }
                ))
                .labelsHidden()
                .tint(BankTheme.positive)
                .disabled(!viewModel.canUseBiometric || viewModel.isWorking)
                .accessibilityIdentifier("settings.faceID")
            }
            SettingsDivider()
            SettingsRow(symbol: "lock.rotation", title: "settings.autoLock") {
                Text("settings.autoLock.value").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
        }
    }

    private var language: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.language")
                .font(BankFont.caption(13, bold: true))
                .foregroundStyle(BankTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            SegmentedTabs(
                items: AppLanguage.allCases,
                selection: viewModel.language,
                title: { $0 == .english ? "language.english" : "language.thai" },
                onSelect: { language in Task { await viewModel.setLanguage(language) } }
            )
            .accessibilityIdentifier("settings.language")
            if viewModel.languagePendingRestart != nil {
                Text("settings.language.restart")
                    .font(BankFont.caption(12))
                    .foregroundStyle(BankTheme.secondaryText)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var notifications: some View {
        SettingsSection(title: "settings.notifications") {
            SettingsRow(symbol: "arrow.left.arrow.right", title: "settings.notify.transactions", subtitle: "settings.notify.transactions.detail") {
                preferenceToggle("settings.notify.transactions", identifier: "settings.notify.transactions", value: \.transactions) {
                    await viewModel.setTransactionAlerts($0)
                }
            }
            SettingsDivider()
            SettingsRow(symbol: "shield.lefthalf.filled", title: "settings.notify.security", subtitle: "settings.notify.security.detail") {
                Text("settings.notify.always").font(BankFont.caption(13, bold: true)).foregroundStyle(BankTheme.positive)
            }
            SettingsDivider()
            SettingsRow(symbol: "gift", title: "settings.notify.marketing") {
                preferenceToggle("settings.notify.marketing", identifier: "settings.notify.marketing", value: \.marketing) {
                    await viewModel.setMarketing($0)
                }
            }
        }
    }

    private func preferenceToggle(
        _ title: LocalizedStringKey,
        identifier: String,
        value: KeyPath<NotificationPreferences, Bool>,
        set: @escaping (Bool) async -> Void
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.profile?.preferences[keyPath: value] ?? false },
            set: { isOn in Task { await set(isOn) } }
        ))
        .labelsHidden()
        .tint(BankTheme.positive)
        .accessibilityIdentifier(identifier)
    }

    private var devices: some View {
        SettingsSection(title: "settings.devices") {
            ForEach(Array(viewModel.devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { SettingsDivider() }
                DeviceRow(device: device)
            }
        }
    }

    private var logout: some View {
        Button(role: .destructive) { isConfirmingLogout = true } label: {
            Text("settings.logout")
                .font(BankFont.body(15, bold: true))
                .foregroundStyle(BankTheme.negative)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(BankTheme.negativeTint, in: RoundedRectangle(cornerRadius: BankTheme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityIdentifier("settings.logout")
    }
}

private struct DeviceRow: View {
    let device: RegisteredDevice

    var body: some View {
        HStack(spacing: 14) {
            IconTile(content: .symbol("iphone"), size: 40, tint: device.isActive ? BankTheme.ink : BankTheme.secondaryText, fill: BankTheme.surfaceSunken)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: device.name).font(BankFont.body(15, bold: true))
                    if device.isCurrent {
                        Text("settings.devices.this")
                            .font(BankFont.caption(11, bold: true))
                            .foregroundStyle(BankTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(BankTheme.accentTint, in: Capsule())
                    }
                }
                if let revoked = device.revokedAt {
                    Text("settings.devices.revoked \(revoked.formatted(date: .abbreviated, time: .omitted))")
                        .font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                } else {
                    Text("settings.devices.since \(device.registeredAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            Spacer()
            if device.isActive {
                Text("settings.devices.active").font(BankFont.caption(12, bold: true)).foregroundStyle(BankTheme.positive)
            }
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}
