import SwiftUI

/// NOTI-03 — everything the bank has told the customer, newest first.
struct InboxView: View {
    @State var viewModel: InboxViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PushedHeader(title: "inbox.title", onBack: onBack) {
                if viewModel.unreadCount > 0 {
                    Button("inbox.readAll") { Task { await viewModel.markAllRead() } }
                        .font(BankFont.caption(13, bold: true))
                        .foregroundStyle(BankTheme.accent)
                        .accessibilityIdentifier("inbox.readAll")
                }
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            content
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BankBackground())
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.failed {
            ErrorStateView { Task { await viewModel.load() } }
                .padding(.horizontal, BankTheme.Spacing.screen)
        } else if viewModel.items.isEmpty, !viewModel.isLoading {
            EmptyStateView(title: "inbox.empty", message: "inbox.empty.detail")
                .padding(.horizontal, BankTheme.Spacing.screen)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.items) { item in
                        Button { Task { await viewModel.open(item) } } label: { InboxRow(item: item) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inbox.item")
                            .onAppear {
                                if item.id == viewModel.items.last?.id { Task { await viewModel.loadMore() } }
                            }
                    }
                    if viewModel.isLoading { ProgressView().padding() }
                }
                .padding(.horizontal, BankTheme.Spacing.screen)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.load() }
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(content: .symbol(symbol), size: 42, tint: tint, fill: fill)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: item.title)
                        .font(BankFont.body(15, bold: !item.isRead))
                        .foregroundStyle(BankTheme.ink)
                    Spacer(minLength: 8)
                    Text(item.createdAt, format: .relative(presentation: .named))
                        .font(BankFont.caption(11))
                        .foregroundStyle(BankTheme.secondaryText)
                }
                if !item.body.isEmpty {
                    Text(verbatim: item.body)
                        .font(BankFont.caption(13))
                        .foregroundStyle(BankTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !item.isRead {
                Circle().fill(BankTheme.accent).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityLabel(Text("inbox.unreadItem"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardShadow(radius: 18, y: 6, opacity: item.isRead ? 0.04 : 0.09)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.kind {
        // Titles come from the server in the customer's language: "เงินเข้า …" / "Money in …".
        case .transaction: item.title.hasPrefix("เงินเข้า") || item.title.hasPrefix("Money in") ? "arrow.down.left" : "arrow.up.right"
        case .security: "lock.shield"
        case .marketing: "gift"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .transaction: BankTheme.ink
        case .security: BankTheme.negative
        case .marketing: BankTheme.caution
        }
    }

    private var fill: Color {
        switch item.kind {
        case .transaction: BankTheme.surfaceSunken
        case .security: BankTheme.negativeTint
        case .marketing: BankTheme.cautionTint
        }
    }
}
