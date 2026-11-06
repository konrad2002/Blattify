import SwiftUI
import Vision
import VisionKit

/// Full-screen QR scanner. Reports the first recognized Blattify code and keeps scanning
/// (with a hint) when a QR code from another app is in view.
struct QRScannerView: View {
    let onCode: (PlantCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var foreignCodeHint = false
    @State private var didScan = false

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(onPayload: handle)
                    .ignoresSafeArea()
                viewfinderOverlay
            } else {
                unavailableView
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding()
        }
        .sensoryFeedback(.success, trigger: didScan)
    }

    private var viewfinderOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 260, height: 260)
                .shadow(color: .black.opacity(0.3), radius: 8)
                .accessibilityHidden(true)
            Text(foreignCodeHint ? "This isn't a Blattify code." : "Point the camera at a plant label.")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect()
                .animation(.default, value: foreignCodeHint)
            Spacer()
        }
        .padding()
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Scanner unavailable", systemImage: "qrcode.viewfinder")
        } description: {
            if DataScannerViewController.isSupported {
                Text("Blattify needs access to the camera to scan plant labels.")
            } else {
                Text("This device can't scan QR codes. Enter the code manually instead.")
            }
        } actions: {
            if DataScannerViewController.isSupported, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func handle(_ payload: String) {
        guard !didScan else { return }
        guard let code = PlantCode(payload: payload) else {
            foreignCodeHint = true
            return
        }
        didScan = true
        // The presenter dismisses the scanner and opens the plant.
        onCode(code)
    }
}

/// Wraps VisionKit's `DataScannerViewController`, limited to QR codes.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        // Scanning can only start once the view controller is on screen.
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onPayload(payload)
                }
            }
        }
    }
}

#Preview {
    QRScannerView { _ in }
}
