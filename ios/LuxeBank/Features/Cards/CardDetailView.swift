import SwiftUI

/// S16 — reveal with Face ID, freeze, channels, daily limit and report lost (CARD-03…07).
struct CardDetailView: View {
    @State var viewModel: CardDetailViewModel
    var revealOnAppear = false
    @State private var confirmingLost = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                numberPanel
                InlineError(message: viewModel.isEnteringPin ? nil : viewModel.error)
                freezeRow
                channels
                dailyLimit
                Button(role: .destructive) { confirmingLost = true } label: {
                    Text("cards.reportLost")
                        .font(BankFont.body(15, bold: true))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(BankTheme.negative)
                        .background(BankTheme.negativeTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0xF3C9C4), lineWidth: 1))
                }
                .accessibilityIdentifier("cards.reportLost")
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("cards.manage").font(BankFont.headline(17))
                    Text(verbatim: "\(viewModel.card.productName) · \(viewModel.card.last4)")
                        .font(BankFont.caption(12))
                        .foregroundStyle(BankTheme.secondaryText)
                }
            }
        }
        .task { if revealOnAppear { await viewModel.reveal() } }
        // Card details never stay on screen in the App Switcher, a recording or after leaving the screen.
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewModel.hide() } }
        .onChange(of: isSceneCaptured) { _, captured in if captured { viewModel.hide() } }
        .onDisappear { viewModel.hide() }
        .confirmationDialog("cards.reportLost.title", isPresented: $confirmingLost, titleVisibility: .visible) {
            Button("cards.reportLost.confirm", role: .destructive) { viewModel.startReportLost() }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("cards.reportLost.message")
        }
        .sheet(isPresented: Binding(get: { viewModel.isEnteringPin }, set: { if !$0 { viewModel.cancelReportLost() } })) { pinSheet }
    }

    private var numberPanel: some View {
        let secrets = viewModel.secrets
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("cards.number").font(BankFont.caption(12, bold: true)).foregroundStyle(Color(hex: 0x3A404C))
                Text(verbatim: secrets?.formattedPAN ?? "•••• •••• •••• \(viewModel.card.last4)")
                    .font(BankFont.body(21, bold: true)).tracking(2).monospacedDigit()
                    .privacySensitive()
                    .accessibilityIdentifier("cards.pan")
            }
            HStack(spacing: 28) {
                field("cards.expiry", viewModel.card.expiry)
                field("cards.cvv", secrets?.cvv ?? "•••")
                if secrets != nil {
                    field("cards.hidesIn", String(format: "0:%02d", viewModel.secondsLeft), tint: BankTheme.accent)
                }
            }
            Button {
                if secrets == nil { Task { await viewModel.reveal() } } else { viewModel.hide() }
            } label: {
                if viewModel.isWorking && secrets == nil {
                    ProgressView().tint(.white)
                } else {
                    Label(secrets == nil ? "cards.revealWithFaceID" : "cards.hideDetails", systemImage: secrets == nil ? "faceid" : "eye.slash")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("cards.reveal")
        }
        .padding(20)
        .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white, lineWidth: 1))
        .cardShadow(radius: 40, y: 20, opacity: 0.18)
    }

    private func field(_ title: LocalizedStringKey, _ value: String, tint: Color = BankTheme.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(BankFont.caption(12, bold: true)).foregroundStyle(Color(hex: 0x3A404C))
            Text(verbatim: value).font(BankFont.body(15, bold: true)).foregroundStyle(tint).monospacedDigit().privacySensitive()
        }
        .accessibilityElement(children: .combine)
    }

    private var freezeRow: some View {
        HStack(spacing: 14) {
            IconTile(content: .symbol("snowflake"), size: 40, tint: BankTheme.accent, fill: BankTheme.accentTint)
            Toggle(isOn: Binding(get: { viewModel.card.isFrozen }, set: { frozen in Task { await viewModel.setFrozen(frozen) } })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("cards.freezeTitle").font(BankFont.body(15, bold: true))
                    Text("cards.freezeHint").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            .tint(BankTheme.accent)
            .accessibilityIdentifier("cards.freezeToggle")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 68)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow(radius: 22, y: 8, opacity: 0.07)
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cards.channels").font(BankFont.caption(13, bold: true)).foregroundStyle(BankTheme.secondaryText).padding(.horizontal, 4)
            VStack(spacing: 0) {
                channel("cards.online", "cards.onlineHint", \.online)
                Divider()
                channel("cards.overseas", "cards.overseasHint", \.overseas)
                Divider()
                channel("cards.contactless", "cards.contactlessHint", \.contactless)
                Divider()
                channel("cards.atm", "cards.atmHint", \.atm)
            }
            .padding(.horizontal, 18)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .cardShadow(radius: 22, y: 8, opacity: 0.07)
            .disabled(viewModel.card.isFrozen)
            .opacity(viewModel.card.isFrozen ? 0.5 : 1)
        }
    }

    private func channel(_ title: LocalizedStringKey, _ hint: LocalizedStringKey, _ keyPath: WritableKeyPath<CardChannels, Bool>) -> some View {
        Toggle(isOn: Binding(get: { viewModel.card.channels[keyPath: keyPath] }, set: { isOn in Task { await viewModel.setChannel(keyPath, isOn) } })) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(BankFont.body(15, bold: true))
                Text(hint).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
            }
        }
        .tint(BankTheme.accent)
        .frame(minHeight: 64)
    }

    private var dailyLimit: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("cards.dailyLimit").font(BankFont.caption(13, bold: true)).foregroundStyle(BankTheme.secondaryText)
                Spacer()
                Text("cards.maxLimit \(BankFormatter.currencyParts(viewModel.card.maxDailyLimit).main)")
                    .font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
            }
            Text(verbatim: BankFormatter.currencyParts(Decimal(viewModel.dailyLimitDraft)).main).font(BankFont.figure(28)).monospacedDigit()
            Slider(
                value: $viewModel.dailyLimitDraft,
                in: NSDecimalNumber(decimal: CardDetailViewModel.limitStep).doubleValue...NSDecimalNumber(decimal: viewModel.card.maxDailyLimit).doubleValue,
                step: NSDecimalNumber(decimal: CardDetailViewModel.limitStep).doubleValue
            ) { editing in
                if !editing { Task { await viewModel.commitDailyLimit() } }
            }
            .tint(BankTheme.accent)
            .accessibilityIdentifier("cards.dailyLimitSlider")
        }
        .surfaceCard(radius: 24, padding: 18)
        .disabled(viewModel.card.isFrozen)
    }

    private var pinSheet: some View {
        VStack(spacing: 24) {
            Text("cards.reportLost.pin").font(BankFont.headline(20)).padding(.top, 28)
            PinDots(filled: viewModel.pin.count, isError: viewModel.error != nil)
            InlineError(message: viewModel.error)
            Spacer(minLength: 0)
            PinPad(onDigit: { digit in Task { await viewModel.appendPinDigit(digit) } }, onDelete: viewModel.deletePinDigit)
                .disabled(viewModel.isWorking)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(BankBackground())
        .interactiveDismissDisabled(viewModel.isWorking)
    }
}
