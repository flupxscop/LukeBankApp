import SwiftUI

/// PROF-07 — chat with the relationship manager. In the simulation the conversation stays on the phone
/// and an automatic reply confirms receipt; a real system would plug a messaging service in here.
struct RMChatView: View {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let fromCustomer: Bool
    }

    let manager: RelationshipManager
    @State private var messages: [Message] = []
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        Text("chat.simulated")
                            .font(BankFont.caption(11))
                            .foregroundStyle(BankTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, BankTheme.Spacing.screen)
                }
                .onChange(of: messages) { _, all in
                    if let last = all.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .background(BankBackground())
        .onAppear {
            if messages.isEmpty {
                messages = [Message(text: String(localized: "chat.greeting \(manager.name)"), fromCustomer: false)]
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(BankTheme.ink).frame(width: 40, height: 40)
                .overlay { Text(verbatim: String(manager.name.prefix(1))).font(BankFont.headline(16)).foregroundStyle(.white) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: manager.name).font(BankFont.body(15, bold: true))
                Text(verbatim: manager.hours).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BankTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(BankTheme.surface, in: Circle())
            }
            .accessibilityLabel(Text("common.close"))
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 12)
    }

    private func bubble(_ message: Message) -> some View {
        HStack {
            if message.fromCustomer { Spacer(minLength: 48) }
            Text(verbatim: message.text)
                .font(BankFont.body(15))
                .foregroundStyle(message.fromCustomer ? .white : BankTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.fromCustomer ? BankTheme.ink : BankTheme.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if !message.fromCustomer { Spacer(minLength: 48) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("chat.placeholder", text: $draft, axis: .vertical)
                .font(BankFont.body(15))
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("chat.input")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(BankTheme.ink, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text("chat.send"))
            .accessibilityIdentifier("chat.send")
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let isFirst = !messages.contains(where: \.fromCustomer)
        messages.append(Message(text: String(text.prefix(500)), fromCustomer: true))
        guard isFirst else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            messages.append(Message(text: String(localized: "chat.autoReply"), fromCustomer: false))
        }
    }
}
