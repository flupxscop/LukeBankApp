import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI

/// S11 — success and the shareable slip with a verification QR (TRF-10).
struct SlipView: View {
    let slip: PaymentSlip
    var showsSuccess = true
    let onDone: () -> Void
    @State private var renderedSlip: UIImage?
    @State private var saved = false
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showsSuccess {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(BankTheme.positive, in: Circle())
                            .shadow(color: BankTheme.positive.opacity(0.35), radius: 14, y: 12)
                        Text(slip.kind == .bill ? "slip.billSuccess" : "slip.transferSuccess")
                            .font(BankFont.title(24))
                            .accessibilityIdentifier("slip.title")
                        Text(verbatim: BankFormatter.dateTime(slip.occurredAt))
                            .font(BankFont.caption(13))
                            .foregroundStyle(BankTheme.secondaryText)
                    }
                    .padding(.top, 12)
                }
                SlipCard(slip: slip)
                actions
                if saveFailed {
                    InlineError(message: "slip.saveFailed")
                }
            }
            .padding(.horizontal, BankTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .background(BankBackground())
        .navigationBarBackButtonHidden(showsSuccess)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomAction(title: "slip.done", identifier: "slip.done", action: onDone)
        }
        .task { renderedSlip = render() }
        .sensoryFeedback(.success, trigger: showsSuccess)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                guard let renderedSlip else { return }
                Task { await save(renderedSlip) }
            } label: {
                Label(saved ? "slip.saved" : "slip.save", systemImage: saved ? "checkmark" : "arrow.down.to.line")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(renderedSlip == nil || saved)
            .accessibilityIdentifier("slip.save")

            if let renderedSlip {
                ShareLink(
                    item: Image(uiImage: renderedSlip),
                    preview: SharePreview(Text("slip.shareTitle"), image: Image(uiImage: renderedSlip))
                ) {
                    Label("slip.share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// Add-only Photos access; reports a refusal instead of claiming success.
    private func save(_ image: UIImage) async {
        saveFailed = false
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveFailed = true
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            saved = true
        } catch {
            saveFailed = true
        }
    }

    @MainActor
    private func render() -> UIImage? {
        let renderer = ImageRenderer(content: SlipCard(slip: slip).frame(width: 350).padding(20).background(BankTheme.porcelain))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The slip itself; rendered on screen and into the saved image.
struct SlipCard: View {
    let slip: PaymentSlip

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(verbatim: "LUXEBANK").font(BankFont.caption(13, bold: true)).tracking(4)
                    Spacer()
                    Text(verbatim: slip.referenceNo).font(BankFont.caption(11)).foregroundStyle(BankTheme.secondaryText)
                        .accessibilityIdentifier("slip.reference")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("confirm.amount").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                    Text(verbatim: BankFormatter.currency(slip.amount)).font(BankFont.figure(34)).monospacedDigit()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)

            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .foregroundStyle(BankTheme.lineStrong)
                .frame(height: 1)
                .padding(.horizontal, 18)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    party("confirm.from", slip.from)
                    party("confirm.to", slip.to)
                    if let memo = slip.memo {
                        Text(verbatim: memo).font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                    }
                    Text("slip.fee \(BankFormatter.currency(slip.fee))").font(BankFont.caption(12)).foregroundStyle(BankTheme.secondaryText)
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    QRCodeImage(payload: slip.slipQR).frame(width: 86, height: 86)
                    Text("slip.scanToVerify").font(BankFont.caption(10)).foregroundStyle(BankTheme.secondaryText)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .background(BankTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: BankTheme.shadow.opacity(0.14), radius: 25, y: 24)
        .accessibilityElement(children: .combine)
    }

    private func party(_ label: LocalizedStringKey, _ party: PaymentParty) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(BankFont.caption(11)).foregroundStyle(BankTheme.secondaryText)
            Text(verbatim: party.name).font(BankFont.caption(13, bold: true))
            if let detail = [party.bankName, party.account].compactMap({ $0 }).joined(separator: " · ").nilIfBlank {
                Text(verbatim: detail).font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
        }
    }
}

/// Crisp QR from Core Image; nothing leaves the device.
struct QRCodeImage: View {
    let payload: String

    var body: some View {
        if let image = Self.make(payload) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                .accessibilityLabel(Text("slip.qr"))
        } else {
            Color.clear
        }
    }

    static func make(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
