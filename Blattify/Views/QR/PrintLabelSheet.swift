import SwiftUI

/// Finds nearby P22 printers, connects to the chosen one, shows its status and prints the plant's
/// label (code above the QR code). The printer is disconnected when the sheet closes.
struct PrintLabelSheet: View {
    let plant: Plant

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var printer = P22PrinterManager()

    private var label: Result<P22LabelRenderer.Label, P22LabelRenderer.RenderError> {
        guard let code = PlantCode(plant.code) else { return .failure(.invalidHeading) }
        return Result { () throws(P22LabelRenderer.RenderError) in
            try P22LabelRenderer.label(qrText: code.url.absoluteString, heading: code.rawValue)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                previewSection
                switch printer.phase {
                case .starting:
                    Section { ProgressView() }
                case .bluetoothOff:
                    messageSection("Bluetooth is turned off", systemImage: "antenna.radiowaves.left.and.right.slash",
                                   text: "Turn on Bluetooth in Control Center or the Settings app to find your printer.")
                case .unauthorized:
                    messageSection("No Bluetooth access", systemImage: "lock",
                                   text: "Allow Blattify to use Bluetooth in the Settings app to connect to your printer.",
                                   showsSettingsButton: true)
                case .unsupported:
                    messageSection("Bluetooth not available", systemImage: "exclamationmark.triangle",
                                   text: "This device does not support Bluetooth Low Energy.")
                case .scanning:
                    printerListSection
                case .connecting(let name):
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting to \(name)…")
                        }
                    }
                case .ready(let name):
                    statusSection(name: name)
                    printSection
                case .failed(let message, let details):
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            if let details {
                                Text(verbatim: details)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Button("Search again", systemImage: "arrow.clockwise") {
                            printer.chooseAnotherPrinter()
                        }
                    }
                }
            }
            .navigationTitle("Print label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(printer.isSending)
                }
            }
        }
        // Closing during a transfer would leave a half-printed label.
        .interactiveDismissDisabled(printer.isSending)
        .onAppear { printer.start() }
        .onDisappear { printer.shutdown() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var previewSection: some View {
        Section {
            switch label {
            case .success(let label):
                if let image = P22LabelRenderer.image(fromRaster: label.raster) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96 * 2.5, height: 112 * 2.5)
                        .padding(12)
                        .background(.white, in: .rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Label preview with code \(plant.code)"))
                }
            case .failure:
                Label("This label cannot be printed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Printed at 96 × 112 pixels on 15 × 14 mm labels.")
        }
        .listRowBackground(Color.clear)
    }

    private var printerListSection: some View {
        Section {
            if printer.printers.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching for printers…")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(printer.printers) { candidate in
                Button {
                    printer.connect(to: candidate)
                } label: {
                    HStack {
                        Label(candidate.name, systemImage: "printer")
                        Spacer()
                        SignalStrength(rssi: candidate.rssi)
                    }
                }
            }
        } header: {
            Text("Nearby printers")
        } footer: {
            Text("Switch the printer on and keep it close to your iPhone.")
        }
    }

    private func statusSection(name: String) -> some View {
        Section {
            LabeledContent {
                Text(verbatim: name)
            } label: {
                Label("Printer", systemImage: "printer.fill")
            }
            LabeledContent {
                statusValue(payload: printer.status.batteryPayload, failed: printer.status.batteryQueryFailed)
            } label: {
                Label("Battery", systemImage: "battery.75percent")
            }
            LabeledContent {
                Text("\(P22Protocol.labelSizeMillimeters.width) × \(P22Protocol.labelSizeMillimeters.height) mm")
            } label: {
                Label("Label size", systemImage: "rectangle.portrait")
            }
            LabeledContent {
                statusValue(payload: printer.status.configPayload, failed: printer.status.configQueryFailed)
            } label: {
                Label("Paper", systemImage: "doc")
            }
            Button("Choose another printer", systemImage: "arrow.left.arrow.right") {
                printer.chooseAnotherPrinter()
            }
            .disabled(printer.isSending)
        } header: {
            Text("Connected")
        } footer: {
            Text("The printer reports battery and paper information in a format that is not decoded yet. The raw values are shown for reference.")
        }
    }

    /// "Not decoded yet" plus the raw bytes, or "No response".
    @ViewBuilder
    private func statusValue(payload: Data?, failed: Bool) -> some View {
        if let payload {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Not decoded yet")
                Text(verbatim: payload.hexString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else if failed {
            Text("No response")
                .foregroundStyle(.orange)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var printSection: some View {
        Section {
            switch printer.printState {
            case .idle:
                EmptyView()
            case .preparing:
                ProgressView("Preparing printer…")
            case .sending(let progress):
                ProgressView(value: progress) {
                    Text("Sending label…")
                }
            case .sent:
                Label("Label sent to the printer.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message, let mayBePartial):
                VStack(alignment: .leading, spacing: 4) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    if mayBePartial {
                        Text("Check the label before printing again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                guard case .success(let label) = label,
                      let job = try? P22Protocol.printJob(raster: label.raster) else { return }
                Task { await printer.print(job) }
            } label: {
                Label(printer.printState == .sent ? "Print again" : "Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(printer.isSending || (try? label.get()) == nil)
            .listRowBackground(Color.clear)
        }
    }

    private func messageSection(_ title: LocalizedStringKey, systemImage: String, text: LocalizedStringKey,
                                showsSettingsButton: Bool = false) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(text)
            } actions: {
                if showsSettingsButton, let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(url) }
                }
            }
        }
    }
}

/// Signal strength as bars plus dBm.
private struct SignalStrength: View {
    let rssi: Int

    var body: some View {
        let level: Double = if rssi >= -60 {
            1
        } else if rssi >= -75 {
            0.66
        } else if rssi >= -90 {
            0.33
        } else {
            0.1
        }
        HStack(spacing: 6) {
            Image(systemName: "cellularbars", variableValue: level)
            Text(verbatim: "\(rssi) dBm")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Signal \(rssi) dBm"))
    }
}
