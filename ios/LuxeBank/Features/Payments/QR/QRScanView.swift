import PhotosUI
import SwiftUI
import Vision
import VisionKit

/// S12 — scan a Thai QR / bill barcode with the camera or pick a photo (TRF-12, BILL-02).
/// The payload goes to `POST /qr/parse`; nothing is paid until the customer confirms.
@MainActor
@Observable
final class QRScanViewModel {
    private(set) var isParsing = false
    private(set) var error: LocalizedStringResource?
    private var lastPayload: String?
    private let repository: PaymentRepository

    init(repository: PaymentRepository) {
        self.repository = repository
    }

    func handle(_ payload: String) async -> ParsedQR? {
        guard !isParsing, payload != lastPayload else { return nil }
        lastPayload = payload
        isParsing = true
        error = nil
        defer { isParsing = false }
        do {
            return try await repository.parseQR(payload)
        } catch {
            self.error = PaymentErrors.message(for: error)
            lastPayload = nil
            return nil
        }
    }

    func handle(image data: Data) async -> ParsedQR? {
        guard let payload = Self.detect(in: data) else {
            error = "error.qrNotFound"
            return nil
        }
        return await handle(payload)
    }

    /// Finds the first QR or barcode in a picked image, on device.
    nonisolated static func detect(in data: Data) -> String? {
        guard let image = CIImage(data: data) else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .code128]
        try? VNImageRequestHandler(ciImage: image).perform([request])
        return request.results?.compactMap(\.payloadStringValue).first
    }
}

struct QRScanView: View {
    @State var viewModel: QRScanViewModel
    let onClose: () -> Void
    let onResult: (ParsedQR) -> Void
    @State private var photo: PhotosPickerItem?

    private var cameraAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ZStack(alignment: .bottom) {
            camera.ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .accessibilityLabel(Text("common.close"))
                    Spacer()
                    Text("qr.title").font(BankFont.headline(16)).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, BankTheme.Spacing.screen)
                Spacer()
                frame
                Spacer()
                Spacer()
            }
            .padding(.top, 8)
            sheet
        }
        .background(Color(hex: 0x101216))
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let result = await viewModel.handle(image: data) {
                    onResult(result)
                }
                photo = nil
            }
        }
    }

    @ViewBuilder
    private var camera: some View {
        if cameraAvailable {
            DataScanner { payload in
                Task { if let result = await viewModel.handle(payload) { onResult(result) } }
            }
        } else {
            RadialGradient(colors: [Color(hex: 0x3A3F4A), Color(hex: 0x101216)], center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: 420)
        }
    }

    private var frame: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .stroke(.white, style: StrokeStyle(lineWidth: 3, dash: [44, 152], dashPhase: 22))
            .frame(width: 240, height: 240)
            .overlay {
                if viewModel.isParsing { ProgressView().tint(.white).controlSize(.large) }
            }
            .accessibilityHidden(true)
    }

    private var sheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color(hex: 0xC9CED8)).frame(width: 40, height: 5)
            VStack(spacing: 4) {
                Text(cameraAvailable ? "qr.instruction" : "qr.noCamera").font(BankFont.headline(17)).multilineTextAlignment(.center)
                Text("qr.supported").font(BankFont.caption(13)).foregroundStyle(BankTheme.secondaryText)
            }
            InlineError(message: viewModel.error)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("qr.fromPhotos", systemImage: "photo")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("qr.photos")
        }
        .padding(.horizontal, BankTheme.Spacing.screen)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(BankTheme.porcelain, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
    }
}

/// VisionKit live scanner for QR codes and invoice barcodes.
private struct DataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .code128])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue {
                    onPayload(payload)
                    return
                }
            }
        }
    }
}
