import CoreBluetooth
import Foundation

/// Scans for, connects to and prints on P22 label printers over Core Bluetooth.
/// Created when the print dialog opens (which triggers the Bluetooth permission prompt) and shut down
/// when it closes. All delegate callbacks arrive on the main queue.
@Observable
final class P22PrinterManager: NSObject {
    struct DiscoveredPrinter: Identifiable {
        let id: UUID
        let name: String
        var rssi: Int
        let peripheral: CBPeripheral
    }

    enum Phase: Equatable {
        case starting
        case bluetoothOff
        case unauthorized
        case unsupported
        case scanning
        case connecting(name: String)
        case ready(name: String)
        case failed(message: String)
    }

    enum PrintState: Equatable {
        case idle
        case preparing
        case sending(progress: Double)
        case sent
        /// `mayBePartial`: some bytes were already sent, so a partial label may have been printed.
        case failed(message: String, mayBePartial: Bool)
    }

    /// Raw status responses. Their meaning is not decoded yet (see `P22_PROTOCOL.md`).
    struct Status: Equatable {
        var batteryPayload: Data?
        var configPayload: Data?
        var batteryQueryFailed = false
        var configQueryFailed = false
    }

    private(set) var phase: Phase = .starting
    private(set) var printers: [DiscoveredPrinter] = []
    private(set) var status = Status()
    private(set) var printState: PrintState = .idle

    var isSending: Bool {
        if case .sending = printState { return true }
        return printState == .preparing
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var responseCharacteristic: CBCharacteristic?
    @ObservationIgnored private var pendingResponse: (id: UUID, continuation: CheckedContinuation<Data?, Never>)?
    @ObservationIgnored private var readyToWrite: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var connectTimeout: Task<Void, Never>?

    private static let responseTimeout: Duration = .seconds(3)
    private static let connectionTimeout: Duration = .seconds(15)

    // MARK: - Lifecycle

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Stops scanning, disconnects and releases Bluetooth (called when the dialog closes).
    func shutdown() {
        central?.stopScan()
        disconnect()
        central?.delegate = nil
        central = nil
    }

    func startScanning() {
        guard let central, central.state == .poweredOn else { return }
        printers = []
        phase = .scanning
        // No service filter: the name "P22" and the advertised service AF30 are both only candidate hints.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(to printer: DiscoveredPrinter) {
        guard let central else { return }
        central.stopScan()
        peripheral = printer.peripheral
        printer.peripheral.delegate = self
        status = Status()
        printState = .idle
        phase = .connecting(name: printer.name)
        central.connect(printer.peripheral)
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.connectionTimeout)
            guard let self, !Task.isCancelled, case .connecting = self.phase else { return }
            self.fail(String(localized: "The printer did not respond. Make sure it is switched on and nearby."))
        }
    }

    func disconnect() {
        connectTimeout?.cancel()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
    }

    /// Disconnects and scans again (e.g. to choose another printer).
    func chooseAnotherPrinter() {
        disconnect()
        startScanning()
    }

    // MARK: - Printing

    /// Sends the pre-print queries observed from the original app, then the job in ordered chunks.
    func print(_ job: Data) async {
        guard case .ready = phase, let peripheral, let writeCharacteristic else { return }
        printState = .preparing

        // Same preamble as the successfully replayed capture (meaning unknown).
        for query in [P22Protocol.unknownQueryA, P22Protocol.unknownQueryB,
                      P22Protocol.unknownQueryA, P22Protocol.unknownQueryB] {
            _ = await request(query)
            guard isConnected else {
                printState = .failed(message: String(localized: "The connection to the printer was lost."), mayBePartial: false)
                return
            }
        }

        let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let chunks = P22Protocol.chunks(of: job, maxLength: maxLength)
        var sent = 0
        printState = .sending(progress: 0)
        for chunk in chunks {
            await waitUntilReadyToWrite()
            guard isConnected else {
                printState = .failed(message: String(localized: "The connection to the printer was lost. The label may be incomplete."),
                                     mayBePartial: sent > 0)
                return
            }
            peripheral.writeValue(chunk, for: writeCharacteristic, type: .withoutResponse)
            sent += chunk.count
            printState = .sending(progress: Double(sent) / Double(job.count))
        }
        // There is no known print-complete response; the job was handed to the printer.
        printState = .sent
    }

    // MARK: - Private

    private var isConnected: Bool {
        peripheral?.state == .connected && writeCharacteristic != nil
    }

    private func resetConnection() {
        resolvePendingResponse(nil)
        readyToWrite?.resume()
        readyToWrite = nil
        peripheral?.delegate = nil
        peripheral = nil
        writeCharacteristic = nil
        responseCharacteristic = nil
    }

    private func fail(_ message: String) {
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
        phase = .failed(message: message)
    }

    /// Writes one query and waits for the next `FF01` notification (responses are untagged, so only
    /// one query may be outstanding). Returns `nil` on timeout or disconnect.
    private func request(_ bytes: Data) async -> Data? {
        guard let peripheral, let writeCharacteristic else { return nil }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pendingResponse = (id, continuation)
            peripheral.writeValue(bytes, for: writeCharacteristic, type: .withoutResponse)
            Task { [weak self] in
                try? await Task.sleep(for: Self.responseTimeout)
                guard let self, self.pendingResponse?.id == id else { return }
                self.resolvePendingResponse(nil)
            }
        }
    }

    private func resolvePendingResponse(_ data: Data?) {
        guard let pending = pendingResponse else { return }
        pendingResponse = nil
        pending.continuation.resume(returning: data)
    }

    private func waitUntilReadyToWrite() async {
        guard let peripheral, !peripheral.canSendWriteWithoutResponse, isConnected else { return }
        await withCheckedContinuation { continuation in
            readyToWrite = continuation
        }
    }

    private func queryStatus(printerName: String) async {
        let battery = await request(P22Protocol.batteryQuery)
        status.batteryPayload = battery.flatMap(P22Protocol.batteryPayload(from:))
        status.batteryQueryFailed = status.batteryPayload == nil
        guard isConnected else { return }

        let config = await request(P22Protocol.configQuery)
        status.configPayload = config.flatMap(P22Protocol.configPayload(from:))
        status.configQueryFailed = status.configPayload == nil
        guard isConnected else { return }

        phase = .ready(name: printerName)
    }

    private func printerName(for peripheral: CBPeripheral, advertisement: [String: Any]? = nil) -> String {
        (advertisement?[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? P22GATT.advertisedName
    }
}

// MARK: - CBCentralManagerDelegate

extension P22PrinterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .ready = phase { return }
            startScanning()
        case .poweredOff:
            resetConnection()
            phase = .bluetoothOff
        case .unauthorized:
            phase = .unauthorized
        case .unsupported:
            phase = .unsupported
        case .resetting, .unknown:
            phase = .starting
        @unknown default:
            phase = .starting
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = printerName(for: peripheral, advertisement: advertisementData)
        // Candidates: advertises AF30 or is called P22 (neither is a proven unique identifier).
        guard services.contains(P22GATT.advertisedService) || name.hasPrefix(P22GATT.advertisedName) else { return }
        let rssi = RSSI.intValue
        if let index = printers.firstIndex(where: { $0.id == peripheral.identifier }) {
            if rssi != 127 { printers[index].rssi = rssi }
        } else {
            printers.append(DiscoveredPrinter(id: peripheral.identifier, name: name, rssi: rssi, peripheral: peripheral))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else { return }
        peripheral.discoverServices([P22GATT.printService, P22GATT.auxiliaryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        connectTimeout?.cancel()
        fail(error?.localizedDescription ?? String(localized: "Could not connect to the printer."))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        guard peripheral == self.peripheral else { return }
        connectTimeout?.cancel()
        let wasSending = isSending
        resetConnection()
        if wasSending {
            printState = .failed(message: String(localized: "The connection to the printer was lost. The label may be incomplete."),
                                 mayBePartial: true)
        }
        phase = .failed(message: String(localized: "The printer was disconnected."))
    }
}

// MARK: - CBPeripheralDelegate

extension P22PrinterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == self.peripheral else { return }
        let services = peripheral.services ?? []
        guard error == nil, let printService = services.first(where: { $0.uuid == P22GATT.printService }) else {
            fail(String(localized: "This device does not offer the expected printer service."))
            return
        }
        peripheral.discoverCharacteristics(nil, for: printService)
        if let auxiliary = services.first(where: { $0.uuid == P22GATT.auxiliaryService }) {
            peripheral.discoverCharacteristics(nil, for: auxiliary)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == self.peripheral else { return }
        let characteristics = service.characteristics ?? []

        // Like the original app, also subscribe to FF03 and AE02 (purpose unknown, failures ignored).
        for characteristic in characteristics
        where P22GATT.auxiliaryNotifyCharacteristics.contains(characteristic.uuid) && characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        guard service.uuid == P22GATT.printService else { return }
        let write = characteristics.first { $0.uuid == P22GATT.writeCharacteristic }
        let response = characteristics.first { $0.uuid == P22GATT.responseCharacteristic }
        guard error == nil,
              let write, write.properties.contains(.writeWithoutResponse),
              let response, response.properties.contains(.notify) else {
            fail(String(localized: "This device does not offer the expected printer service."))
            return
        }
        writeCharacteristic = write
        responseCharacteristic = response
        peripheral.setNotifyValue(true, for: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Status queries start only after FF01 notifications are confirmed.
        guard peripheral == self.peripheral, characteristic.uuid == P22GATT.responseCharacteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            fail(String(localized: "The printer could not be prepared for printing."))
            return
        }
        connectTimeout?.cancel()
        let name = printerName(for: peripheral)
        Task { await queryStatus(printerName: name) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic.uuid == P22GATT.responseCharacteristic,
              error == nil, let value = characteristic.value else { return }
        resolvePendingResponse(value)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        readyToWrite?.resume()
        readyToWrite = nil
    }
}
