import SwiftUI

/// PROF-02 — three PIN pads in a sheet: current, new, confirm.
struct ChangePinView: View {
    @State var viewModel: ChangePinViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BankTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(BankTheme.surface, in: Circle())
                }
                .accessibilityLabel(Text("common.close"))
            }
            if viewModel.step == .done {
                done
            } else {
                entry
            }
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BankBackground())
        .interactiveDismissDisabled(viewModel.isWorking)
    }

    private var entry: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(viewModel.title).font(BankFont.title(24)).accessibilityIdentifier("changePin.title")
                Text("pin.setup.subtitle").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
            PinDots(filled: viewModel.pin.count, isError: viewModel.error != nil && viewModel.pin.isEmpty)
            InlineError(message: viewModel.error).frame(minHeight: 18)
            if viewModel.isWorking { ProgressView() }
            Spacer()
            PinPad(onDigit: { digit in Task { await viewModel.appendDigit(digit) } }, onDelete: viewModel.deleteDigit)
                .disabled(viewModel.isWorking)
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            IconTile(content: .symbol("checkmark"), size: 72, tint: BankTheme.positive, fill: BankTheme.positiveTint)
            Text("changePin.done").font(BankFont.title(24))
            Text("changePin.done.detail")
                .font(BankFont.caption(13))
                .foregroundStyle(BankTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
            Button("common.done", action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("changePin.done")
        }
    }
}

extension ChangePinViewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
