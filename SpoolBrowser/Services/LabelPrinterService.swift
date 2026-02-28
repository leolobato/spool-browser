@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "com.leolobato.SpoolBrowser", category: "LabelPrinter")

struct DiscoveredPrinter: Identifiable, Sendable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral

    nonisolated static func == (lhs: DiscoveredPrinter, rhs: DiscoveredPrinter) -> Bool {
        lhs.id == rhs.id
    }
}

enum PrinterConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)
}

enum LabelPrinterError: LocalizedError {
    case notConnected
    case noWriteCharacteristic
    case printFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Printer is not connected."
        case .noWriteCharacteristic:
            "Could not find printer write characteristic."
        case .printFailed(let message):
            message
        }
    }
}

@Observable
@MainActor
final class LabelPrinterService {
    private(set) var connectionState: PrinterConnectionState = .disconnected
    private(set) var discoveredPrinters: [DiscoveredPrinter] = []
    private(set) var isPrinting = false
    private(set) var printProgress: Double = 0

    var printDensity: Int {
        get { UserDefaults.standard.integer(forKey: "labelPrintDensity").clamped(to: 1...8, default: 5) }
        set { UserDefaults.standard.set(newValue, forKey: "labelPrintDensity") }
    }

    var printSpeed: Int {
        get { UserDefaults.standard.integer(forKey: "labelPrintSpeed").clamped(to: 1...5, default: 5) }
        set { UserDefaults.standard.set(newValue, forKey: "labelPrintSpeed") }
    }

    private var bleDelegate: BLEDelegate?
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var useWriteWithResponse = false
    private var pendingScan = false
    private var pendingConnect: CBPeripheral?
    private var autoReconnectTask: Task<Void, Never>?

    private static let lastPrinterUUIDKey = "lastLabelPrinterUUID"

    // BLE Service/Characteristic UUIDs
    private static let serviceUUIDs: [CBUUID] = [
        CBUUID(string: "FF00"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "AE30"),
    ]
    private static let writeCharUUID = CBUUID(string: "FF02")
    private static let notifyCharUUID = CBUUID(string: "FF03")

    init() {
        let delegate = BLEDelegate(service: self)
        self.bleDelegate = delegate
        self.centralManager = CBCentralManager(delegate: delegate, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        discoveredPrinters = []
        guard let central = centralManager else {
            logger.error("startScan: centralManager is nil")
            return
        }

        logger.info("startScan: BLE state = \(String(describing: central.state.rawValue))")
        if central.state == .poweredOn {
            connectionState = .scanning
            logger.info("startScan: scanning for peripherals…")
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false,
            ])
        } else {
            pendingScan = true
            connectionState = .scanning
            logger.info("startScan: BLE not ready, queued pending scan")
        }
    }

    func stopScan() {
        centralManager?.stopScan()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to printer: DiscoveredPrinter) {
        cancelAutoReconnect()
        stopScan()
        connectionState = .connecting
        pendingConnect = printer.peripheral
        centralManager?.connect(printer.peripheral, options: nil)
    }

    func disconnect() {
        cancelAutoReconnect()
        UserDefaults.standard.removeObject(forKey: Self.lastPrinterUUIDKey)
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    func printLabel(rasterData: Data, widthBytes: Int, rows: Int) async throws {
        guard case .connected = connectionState else {
            throw LabelPrinterError.notConnected
        }
        guard writeCharacteristic != nil else {
            throw LabelPrinterError.noWriteCharacteristic
        }

        isPrinting = true
        printProgress = 0

        do {
            // 1. Speed command
            let speed = UInt8(printSpeed)
            try await sendCommand([0x1B, 0x4E, 0x0D, speed])

            // 2. Density command — map app 1-8 → printer ~6-15
            let mappedDensity = UInt8(round(5.0 + Double(printDensity) * 1.25))
            try await sendCommand([0x1B, 0x4E, 0x04, mappedDensity])

            // 3. Media type: labels with gaps
            try await sendCommand([0x1F, 0x11, 0x0A])

            // 4. Raster header
            let wLow = UInt8(widthBytes & 0xFF)
            let rowsLow = UInt8(rows & 0xFF)
            let rowsHigh = UInt8((rows >> 8) & 0xFF)
            try await sendCommand([0x1D, 0x76, 0x30, 0x00, wLow, 0x00, rowsLow, rowsHigh])

            // 5. Image data in 128-byte chunks
            let chunkSize = 128
            let totalBytes = rasterData.count
            var offset = 0

            while offset < totalBytes {
                let end = min(offset + chunkSize, totalBytes)
                let chunk = rasterData[offset..<end]
                try await sendData(Data(chunk))
                try await Task.sleep(for: .milliseconds(20))

                offset = end
                printProgress = Double(offset) / Double(totalBytes)
            }

            // 6. Footer
            try await sendCommand([0x1F, 0xF0, 0x05, 0x00, 0x1F, 0xF0, 0x03, 0x00])

            printProgress = 1.0
        } catch {
            isPrinting = false
            printProgress = 0
            throw error
        }

        isPrinting = false
    }

    // MARK: - Private Helpers

    private func sendCommand(_ bytes: [UInt8]) async throws {
        try await sendData(Data(bytes))
    }

    private func sendData(_ data: Data) async throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            throw LabelPrinterError.notConnected
        }

        let type: CBCharacteristicWriteType = useWriteWithResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func cleanup() {
        connectedPeripheral = nil
        writeCharacteristic = nil
        useWriteWithResponse = false
        connectionState = .disconnected
        isPrinting = false
        printProgress = 0
    }

    // MARK: - BLE Delegate Callbacks (called from BLEDelegate on MainActor)

    fileprivate func centralManagerDidUpdateState(_ state: CBManagerState) {
        logger.info("BLE state changed: \(String(describing: state.rawValue))")
        switch state {
        case .poweredOn:
            if pendingScan {
                pendingScan = false
                connectionState = .scanning
                logger.info("Starting deferred scan…")
                centralManager?.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false,
                ])
            } else if connectedPeripheral == nil {
                attemptAutoReconnect()
            }
        case .poweredOff, .unauthorized, .unsupported:
            logger.warning("BLE unavailable: state=\(String(describing: state.rawValue))")
            cancelAutoReconnect()
            cleanup()
            connectionState = .error("Bluetooth is not available")
        default:
            break
        }
    }

    private static let serviceUUIDStrings: Set<String> = Set(serviceUUIDs.map(\.uuidString))

    // Known Phomemo BLE name prefixes (from phomymo/src/web/ble.js)
    // M110S variants advertise as "Q199..." instead of "M110"
    private static let namePrefixes = [
        "M02", "M03", "M04", "M1", "M2",
        "D1", "D3", "D5",
        "Q1", "Q3",
        "P1", "PM",
        "T0", "A3",
        "Mr.in", "Phomemo",
    ]

    fileprivate func didDiscover(peripheral: CBPeripheral, name: String, advertisedServiceIDs: [String]) {
        let matchesByName = Self.namePrefixes.contains { name.hasPrefix($0) }
        let matchesByService = !advertisedServiceIDs.isEmpty
            && !Set(advertisedServiceIDs).isDisjoint(with: Self.serviceUUIDStrings)

        if !matchesByName && !matchesByService {
            return
        }

        logger.debug("Discovered BLE peripheral: \"\(name)\" services=\(advertisedServiceIDs) (\(peripheral.identifier.uuidString))")

        guard !discoveredPrinters.contains(where: { $0.id == peripheral.identifier }) else {
            logger.debug("Already known: \"\(name)\"")
            return
        }
        logger.info("Found label printer: \"\(name)\" (byName=\(matchesByName), byService=\(matchesByService))")
        discoveredPrinters.append(DiscoveredPrinter(
            id: peripheral.identifier,
            name: name,
            peripheral: peripheral
        ))

        // Auto-reconnect: if this is the saved printer and we're scanning for reconnect
        if autoReconnectTask != nil,
           let savedUUID = UserDefaults.standard.string(forKey: Self.lastPrinterUUIDKey),
           peripheral.identifier.uuidString == savedUUID {
            logger.info("Found saved printer during scan, reconnecting…")
            connect(to: DiscoveredPrinter(id: peripheral.identifier, name: name, peripheral: peripheral))
        }
    }

    fileprivate func didConnect(peripheral: CBPeripheral) {
        cancelAutoReconnect()
        logger.info("Connected to \(peripheral.name ?? "unknown") — discovering services…")
        connectedPeripheral = peripheral
        peripheral.delegate = bleDelegate
        peripheral.discoverServices(Self.serviceUUIDs)
    }

    fileprivate func didFailToConnect(error: Error?) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        pendingConnect = nil
    }

    fileprivate func didDisconnect(peripheral: CBPeripheral) {
        logger.info("Disconnected from \(peripheral.name ?? "unknown")")
        if peripheral.identifier == connectedPeripheral?.identifier {
            cleanup()
        }
    }

    fileprivate func didDiscoverServices(peripheral: CBPeripheral) {
        guard let services = peripheral.services else {
            logger.error("No services found on \(peripheral.name ?? "unknown")")
            connectionState = .error("No services found")
            return
        }

        logger.info("Found \(services.count) service(s): \(services.map { $0.uuid.uuidString })")
        for service in services {
            peripheral.discoverCharacteristics(
                [Self.writeCharUUID, Self.notifyCharUUID],
                for: service
            )
        }
    }

    fileprivate func didDiscoverCharacteristics(peripheral: CBPeripheral, service: CBService) {
        guard let characteristics = service.characteristics else {
            logger.warning("No characteristics for service \(service.uuid.uuidString)")
            return
        }

        logger.info("Service \(service.uuid.uuidString) chars: \(characteristics.map { $0.uuid.uuidString })")
        for char in characteristics {
            if char.uuid == Self.writeCharUUID {
                writeCharacteristic = char
                useWriteWithResponse = !char.properties.contains(.writeWithoutResponse)
                logger.info("Found write characteristic (writeWithResponse=\(self.useWriteWithResponse))")
            } else if char.uuid == Self.notifyCharUUID {
                peripheral.setNotifyValue(true, for: char)
                logger.info("Subscribed to notify characteristic")
            }
        }

        if writeCharacteristic != nil {
            logger.info("Printer ready — connection complete")
            connectionState = .connected
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastPrinterUUIDKey)
        }
    }

    // MARK: - Auto-Reconnect

    private func attemptAutoReconnect() {
        guard let uuidString = UserDefaults.standard.string(forKey: Self.lastPrinterUUIDKey),
              let uuid = UUID(uuidString: uuidString) else { return }

        let peripherals = centralManager?.retrievePeripherals(withIdentifiers: [uuid]) ?? []
        if let peripheral = peripherals.first {
            logger.info("Auto-reconnecting to \(peripheral.name ?? uuid.uuidString)…")
            connectionState = .connecting
            pendingConnect = peripheral
            centralManager?.connect(peripheral, options: nil)
            startAutoReconnectTimeout()
        } else {
            logger.info("Last printer not in range, scanning…")
            connectionState = .scanning
            autoReconnectTask = Task {
                centralManager?.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false,
                ])
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                logger.info("Auto-reconnect scan timed out")
                stopScan()
            }
        }
    }

    private func startAutoReconnectTimeout() {
        autoReconnectTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            if case .connecting = connectionState {
                logger.info("Auto-reconnect timed out")
                if let p = pendingConnect {
                    centralManager?.cancelPeripheralConnection(p)
                }
                pendingConnect = nil
                connectionState = .disconnected
            }
        }
    }

    private func cancelAutoReconnect() {
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
    }

    // MARK: - BLE Delegate

    private final class BLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
        private weak var service: LabelPrinterService?

        init(service: LabelPrinterService) {
            self.service = service
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            Task { @MainActor in
                self.service?.centralManagerDidUpdateState(central.state)
            }
        }

        func centralManager(
            _ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber
        ) {
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
            guard let name else { return }
            Task { @MainActor in
                self.service?.didDiscover(peripheral: peripheral, name: name, advertisedServiceIDs: serviceUUIDs)
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            Task { @MainActor in
                self.service?.didConnect(peripheral: peripheral)
            }
        }

        func centralManager(
            _ central: CBCentralManager,
            didFailToConnect peripheral: CBPeripheral,
            error: Error?
        ) {
            Task { @MainActor in
                self.service?.didFailToConnect(error: error)
            }
        }

        func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral peripheral: CBPeripheral,
            error: Error?
        ) {
            Task { @MainActor in
                self.service?.didDisconnect(peripheral: peripheral)
            }
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            Task { @MainActor in
                self.service?.didDiscoverServices(peripheral: peripheral)
            }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didDiscoverCharacteristicsFor service: CBService,
            error: Error?
        ) {
            Task { @MainActor in
                self.service?.didDiscoverCharacteristics(peripheral: peripheral, service: service)
            }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didUpdateValueFor characteristic: CBCharacteristic,
            error: Error?
        ) {
            // Notification data — not currently needed for printing
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        let val = self == 0 ? defaultValue : self
        return Swift.min(Swift.max(val, range.lowerBound), range.upperBound)
    }
}
