import SwiftUI

/// A payment flow shown full screen from the Payments tab, the home quick actions or a QR scan.
enum PaymentFlow: Identifiable, Hashable {
    case transfer(TransferPrefill?)
    case bills(BillerCategory?, BillTarget?)
    case scan

    var id: String {
        switch self {
        case .transfer(let prefill): "transfer-\(prefill.hashValue)"
        case .bills(let category, let target): "bills-\(category?.rawValue ?? "")-\(target.hashValue)"
        case .scan: "scan"
        }
    }
}

@MainActor
@Observable
final class PaymentsViewModel {
    private(set) var limits: TransferLimits?
    private(set) var favorites: [Payee] = []
    private(set) var bills: [SavedBill] = []
    private(set) var failed = false
    private let repository: PaymentRepository

    init(repository: PaymentRepository) {
        self.repository = repository
    }

    var unpaidBills: [SavedBill] { bills.filter { !$0.paid } }

    func load() async {
        do {
            async let payees = repository.payees()
            async let bills = repository.savedBills()
            let accounts = try await repository.accounts()
            favorites = Array(try await payees.filter(\.favorite).prefix(3))
            self.bills = try await bills
            if let primary = accounts.first { limits = try await repository.limits(accountID: primary.id) }
            failed = false
        } catch {
            failed = true
        }
    }
}

/// S21 — shortcuts, favourites and bills waiting to be paid (TRF-11, BILL-03).
struct PaymentsView: View {
    @State var viewModel: PaymentsViewModel
    let onStart: (PaymentFlow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                tiles
                favorites
                bills
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, BankTheme.Spacing.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(BankBackground())
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("payments")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("tab.payments").font(BankFont.title(32))
            Spacer()
            if let limits = viewModel.limits {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("payments.limitToday").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                    Text(verbatim: BankFormatter.currencyParts(limits.remaining).main).font(BankFont.body(15, bold: true)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
    }

    private var tiles: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Button { onStart(.transfer(nil)) } label: {
                    VStack(alignment: .leading) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(BankTheme.ink)
                            .frame(width: 48, height: 48)
                            .background(.white, in: Circle())
                        Spacer()
                        Text("action.transfer").font(BankFont.headline(22)).foregroundStyle(.white)
                        Text("payments.transferKinds").font(BankFont.caption(12)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 186, alignment: .leading)
                    .background {
                        ZStack(alignment: .topTrailing) {
                            BankTheme.ink
                            Circle().fill(RadialGradient(colors: [BankTheme.glow.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 100))
                                .frame(width: 200, height: 200).offset(x: 80, y: -80)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
                .gridCellUnsizedAxes(.vertical)
                .accessibilityIdentifier("payments.transfer")

                VStack(spacing: 10) {
                    tile(title: "action.payBill", identifier: "payments.bills", flow: .bills(nil, nil)) {
                        Text(verbatim: "\(viewModel.unpaidBills.count)")
                            .font(BankFont.body(15, bold: true))
                            .foregroundStyle(BankTheme.caution)
                            .frame(width: 40, height: 40)
                            .background(BankTheme.cautionTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    tile(title: "action.scan", identifier: "payments.scan", flow: .scan) {
                        IconTile(content: .symbol("qrcode.viewfinder"), size: 40, tint: BankTheme.accent, fill: BankTheme.accentTint)
                    }
                }
            }
            GridRow {
                Button { onStart(.bills(.mobile, nil)) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("action.topUp").font(BankFont.body(16, bold: true))
                            Text("payments.topUpKinds").font(BankFont.caption(12)).foregroundStyle(Color(hex: 0x3A404C))
                        }
                        Spacer()
                        IconTile(content: .symbol("plus"), size: 40)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(BankTheme.silver, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous).stroke(.white, lineWidth: 1))
                    .cardShadow(radius: 22, y: 8, opacity: 0.1)
                }
                .buttonStyle(.plain)
                .gridCellColumns(2)
            }
        }
    }

    private func tile<Badge: View>(title: LocalizedStringKey, identifier: String, flow: PaymentFlow, @ViewBuilder badge: () -> Badge) -> some View {
        Button { onStart(flow) } label: {
            HStack {
                Text(title).font(BankFont.body(16, bold: true)).foregroundStyle(BankTheme.ink)
                Spacer()
                badge()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
            .cardShadow(radius: 22, y: 8, opacity: 0.07)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("payments.favorites").font(BankFont.headline(17))
            HStack(alignment: .top) {
                ForEach(viewModel.favorites) { payee in
                    Button { onStart(.transfer(TransferPrefill(kind: payee.kind, payeeID: payee.id))) } label: {
                        VStack(spacing: 8) {
                            PayeeAvatar(payee: payee)
                            Text(verbatim: payee.displayName).font(BankFont.caption(12, bold: true)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("payments.favorite")
                }
                Button { onStart(.transfer(nil)) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 54, height: 54)
                            .overlay(Circle().stroke(Color(hex: 0xC9CED8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        Text("payments.add").font(BankFont.caption(12, bold: true))
                    }
                    .foregroundStyle(BankTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .surfaceCard(padding: 18)
    }

    @ViewBuilder
    private var bills: some View {
        if !viewModel.bills.isEmpty {
            VStack(spacing: 0) {
                ForEach(viewModel.bills) { bill in
                    Button { onStart(.bills(nil, BillTarget(biller: bill.biller, saved: bill))) } label: { SavedBillRow(bill: bill) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: BankTheme.Radius.card, style: .continuous))
            .cardShadow()
        }
    }
}
