import SwiftUI

/// S10 — review the name-checked payment and confirm with Face ID or PIN (TRF-06, TRF-07, TRF-09).
struct PaymentConfirmView: View {
    @State var viewModel: PaymentConfirmViewModel
    let onSlip: (PaymentSlip) -> Void
    let onExpired: () -> Void

    var body: some View {
        let inquiry = viewModel.inquiry
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text("confirm.amount").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
                    MoneyText(amount: inquiry.amount, size: 48)
                        .accessibilityIdentifier("confirm.amountValue")
                }
                parties(inquiry)
                details(inquiry)
                if viewModel.phase == .expired { expired }
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .background(BankBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("confirm.title").font(BankFont.headline(17)) }
            ToolbarItem(placement: .topBarTrailing) { countdown }
        }
        .navigationBarBackButtonHidden(viewModel.phase == .submitting)
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: pinSheetBinding) { pinSheet }
        .onChange(of: viewModel.slip) { _, slip in
            if let slip { onSlip(slip) }
        }
    }

    // MARK: Sections

    private func parties(_ inquiry: PaymentInquiry) -> some View {
        VStack(spacing: 0) {
            partyRow(label: "confirm.from", party: inquiry.from, monogram: "LX", dark: true, verified: false)
            Rectangle().fill(BankTheme.line).frame(height: 1).padding(.horizontal, 18)
                .overlay {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BankTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(BankTheme.porcelain, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .accessibilityHidden(true)
                }
            partyRow(
                label: "confirm.to",
                party: inquiry.to,
                monogram: inquiry.bill.map { _ in String(inquiry.to.name.prefix(2)) } ?? String((inquiry.to.bankName ?? inquiry.to.name).prefix(1)),
                dark: false,
                verified: true
            )
        }
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .cardShadow()
    }

    private func partyRow(label: LocalizedStringKey, party: PaymentParty, monogram: String, dark: Bool, verified: Bool) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: monogram)
                .font(BankFont.caption(dark ? 10 : 14, bold: true))
                .tracking(dark ? 1.4 : 0)
                .foregroundStyle(dark ? .white : BankTheme.ink)
                .frame(width: 44, height: 44)
                .background(dark ? BankTheme.ink : BankTheme.porcelain, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                Text(verbatim: party.name).font(BankFont.body(15, bold: true)).foregroundStyle(BankTheme.ink)
                if let detail = [party.bankName, party.account].compactMap({ $0 }).joined(separator: " · ").nilIfBlank {
                    Text(verbatim: detail).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            Spacer()
            if verified {
                Label("confirm.verified", systemImage: "checkmark")
                    .font(BankFont.caption(11, bold: true))
                    .foregroundStyle(BankTheme.positive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BankTheme.positiveTint, in: Capsule())
            }
        }
        .padding(18)
        .accessibilityElement(children: .combine)
    }

    private func details(_ inquiry: PaymentInquiry) -> some View {
        VStack(spacing: 0) {
            if let bill = inquiry.bill {
                detailRow("confirm.customer") { Text(verbatim: bill.customerName) }
                if let due = bill.dueDate {
                    detailRow("confirm.dueDate") { Text(due, format: .dateTime.day().month(.abbreviated).year()) }
                }
            }
            detailRow("confirm.fee") { Text(verbatim: BankFormatter.currency(inquiry.fee)).monospacedDigit() }
            if let memo = inquiry.memo {
                detailRow("confirm.memo") { Text(verbatim: memo) }
            }
            if inquiry.kind != .own {
                Toggle(isOn: $viewModel.save) {
                    Text(inquiry.kind == .bill ? "confirm.saveBill" : "confirm.saveFavorite").font(BankFont.body(14, bold: true))
                }
                .tint(BankTheme.accent)
                .frame(minHeight: 52)
                .accessibilityIdentifier("confirm.save")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardShadow(radius: 16, y: 6, opacity: 0.05)
    }

    private func detailRow<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title).font(BankFont.body(14)).foregroundStyle(BankTheme.secondaryText)
            Spacer()
            value().font(BankFont.body(14, bold: true)).foregroundStyle(BankTheme.ink).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(BankTheme.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = viewModel.secondsLeft(at: context.date)
            Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(BankFont.caption(12, bold: true))
                .monospacedDigit()
                .foregroundStyle(seconds < 60 ? BankTheme.negative : BankTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(BankTheme.surface, in: Capsule())
                .onChange(of: seconds) { _, _ in viewModel.tick() }
                .accessibilityLabel(Text("confirm.timeLeft \(seconds / 60) \(seconds % 60)"))
        }
    }

    private var expired: some View {
        VStack(spacing: 10) {
            Text("confirm.expired").font(BankFont.body(15, bold: true))
            Button("confirm.startAgain", action: onExpired)
                .font(BankFont.body(14, bold: true))
                .foregroundStyle(BankTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 18)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let error = viewModel.error, viewModel.phase != .enteringPin {
                InlineError(message: error)
            } else if viewModel.inquiry.requiresBiometric {
                Text("confirm.stepUpNote").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
            }
            Button {
                Task { await viewModel.confirm() }
            } label: {
                if viewModel.phase == .submitting {
                    ProgressView().tint(.white)
                } else {
                    Label(
                        viewModel.usesBiometric ? "confirm.withFaceID" : "confirm.withPIN",
                        systemImage: viewModel.usesBiometric ? "faceid" : "circle.grid.3x3"
                    )
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.phase != .review)
            .accessibilityIdentifier("confirm.submit")
            if viewModel.usesBiometric, viewModel.canUsePin, viewModel.phase == .review {
                Button("confirm.usePIN", action: viewModel.startPin)
                    .font(BankFont.caption(13, bold: true))
                    .foregroundStyle(BankTheme.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(BankTheme.porcelain.opacity(0.95))
    }

    private var pinSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .enteringPin || (viewModel.phase == .submitting && !viewModel.pin.isEmpty) },
            set: { isPresented in if !isPresented, viewModel.phase == .enteringPin { viewModel.cancelPin() } }
        )
    }

    private var pinSheet: some View {
        VStack(spacing: 24) {
            Text("confirm.enterPIN").font(BankFont.headline(20)).padding(.top, 28)
            PinDots(filled: viewModel.pin.count, isError: viewModel.error != nil)
            InlineError(message: viewModel.error)
            Spacer(minLength: 0)
            PinPad(onDigit: { digit in Task { await viewModel.appendPinDigit(digit) } }, onDelete: viewModel.deletePinDigit)
                .disabled(viewModel.phase == .submitting)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(BankBackground())
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.phase == .submitting)
    }
}
