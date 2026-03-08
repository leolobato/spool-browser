import SwiftUI

struct SettingsView: View {
    @AppStorage("spoolmanURL") private var spoolmanURL = ""

    @State private var testingSpoolman = false
    @State private var spoolmanResult: TestResult?
    @FocusState private var spoolmanURLFocused: Bool

    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService
    var labelPrinterService: LabelPrinterService

    @State private var testingHelper = false
    @State private var helperResult: TestResult?

    @State private var checkingFields = false
    @State private var missingFields: [String] = []
    @State private var showFieldsConfirmation = false
    @State private var showFieldsResult = false
    @State private var fieldsResultTitle = ""
    @State private var fieldsResultMessage = ""

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if spoolmanService.isConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else if spoolmanService.isConfigured {
                            Label("Not connected", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            Label("Not configured", systemImage: "circle")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    TextField("URL (e.g. http://192.168.1.100:7912)", text: $spoolmanURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($spoolmanURLFocused)
                        .onChange(of: spoolmanURL) {
                            spoolmanService.configure(baseURL: spoolmanURL)
                        }
                        .onSubmit {
                            checkSpoolmanConnection()
                        }
                        .onChange(of: spoolmanURLFocused) {
                            if !spoolmanURLFocused {
                                checkSpoolmanConnection()
                            }
                        }

                    testButton(
                        label: "Test Connection",
                        isTesting: testingSpoolman,
                        result: spoolmanResult,
                        disabled: spoolmanURL.isEmpty,
                        action: testSpoolmanConnection
                    )
                } header: {
                    Text("Spoolman")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if spoolHelperService.isDiscovered {
                            Label(spoolHelperService.discoveredName ?? "Found", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else {
                            Label("Not found", systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    TextField("IP:Port (e.g. 192.168.1.42:12345)", text: Binding(
                        get: { spoolHelperService.manualAddress },
                        set: { spoolHelperService.manualAddress = $0 }
                    ))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    testButton(
                        label: "Test Connection",
                        isTesting: testingHelper,
                        result: helperResult,
                        disabled: !spoolHelperService.isAvailable,
                        action: testHelperConnection
                    )
                } header: {
                    Text("SpoolHelper")
                } footer: {
                    Text("Auto-discovered via Bonjour, or enter the address manually.")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        extraFieldsStatusLabel
                    }

                    if !spoolmanService.extraFieldsStatus.isAllPresent {
                        Button {
                            checkMissingFields()
                        } label: {
                            HStack {
                                Text("Create Custom Fields")
                                Spacer()
                                if checkingFields {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(!spoolmanService.isConfigured || checkingFields)
                    }
                } header: {
                    Text("Spoolman Extra Fields")
                } footer: {
                    Text("Custom filament fields in Spoolman for slicer profile data.")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        printerStatusLabel
                    }

                    switch labelPrinterService.connectionState {
                    case .disconnected, .error:
                        Button {
                            labelPrinterService.startScan()
                        } label: {
                            Label("Scan for Printers", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    case .scanning:
                        ForEach(labelPrinterService.discoveredPrinters) { printer in
                            Button {
                                labelPrinterService.connect(to: printer)
                            } label: {
                                Label(printer.name, systemImage: "printer")
                            }
                        }
                        Button {
                            labelPrinterService.stopScan()
                        } label: {
                            HStack {
                                Label("Scanning...", systemImage: "magnifyingglass")
                                Spacer()
                                ProgressView()
                            }
                        }
                    case .connecting:
                        Button {
                            labelPrinterService.disconnect()
                        } label: {
                            HStack {
                                Label("Connecting...", systemImage: "printer")
                                Spacer()
                                ProgressView()
                            }
                        }
                    case .connected:
                        Stepper(
                            "Density: \(labelPrinterService.printDensity)",
                            value: Binding(
                                get: { labelPrinterService.printDensity },
                                set: { labelPrinterService.printDensity = $0 }
                            ),
                            in: 1...8
                        )
                        Stepper(
                            "Speed: \(labelPrinterService.printSpeed)",
                            value: Binding(
                                get: { labelPrinterService.printSpeed },
                                set: { labelPrinterService.printSpeed = $0 }
                            ),
                            in: 1...5
                        )
                        Button {
                            labelPrinterService.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Label Printer")
                } footer: {
                    Text("Connect to a Phomemo M110 label printer via Bluetooth.")
                }
            }
            .navigationTitle("Settings")
            .task {
                if spoolmanService.isConnected {
                    await spoolmanService.checkExtraFields()
                }
            }
            .onChange(of: spoolmanService.isConnected) {
                if spoolmanService.isConnected {
                    Task {
                        await spoolmanService.checkExtraFields()
                    }
                }
            }
            .alert("Create Custom Fields", isPresented: $showFieldsConfirmation) {
                Button("Create", role: .destructive) {
                    createFields()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The following fields will be created on Spoolman:\n\n\(missingFields.joined(separator: "\n"))")
            }
            .alert(fieldsResultTitle, isPresented: $showFieldsResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fieldsResultMessage)
            }
        }
    }

    private func testButton(
        label: String,
        isTesting: Bool,
        result: TestResult?,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: action) {
                HStack {
                    Text(label)
                    Spacer()
                    if isTesting {
                        ProgressView()
                    } else if let result {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .disabled(disabled || isTesting)

            if let result {
                switch result {
                case .success(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failure(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var extraFieldsStatusLabel: some View {
        switch spoolmanService.extraFieldsStatus {
        case .unknown:
            Label("Not checked", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        case .checking:
            Label("Checking...", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        case .allPresent:
            Label("All configured", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        case .missing(let count):
            Label("\(count) missing", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
        case .error:
            Label("Check failed", systemImage: "xmark.circle")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var printerStatusLabel: some View {
        switch labelPrinterService.connectionState {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        case .scanning:
            Label("Scanning", systemImage: "magnifyingglass")
                .foregroundStyle(.orange)
                .font(.subheadline)
        case .connecting:
            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .font(.subheadline)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
    }

    private func checkSpoolmanConnection() {
        spoolmanResult = nil
        guard spoolmanService.isConfigured else { return }
        Task {
            await spoolmanService.checkConnection()
        }
    }

    private func testSpoolmanConnection() {
        testingSpoolman = true
        spoolmanResult = nil
        Task {
            do {
                try await spoolmanService.testConnection()
                spoolmanResult = .success("Connected")
            } catch {
                spoolmanResult = .failure(error.localizedDescription)
            }
            testingSpoolman = false
            await spoolmanService.checkConnection()
        }
    }

    private func testHelperConnection() {
        testingHelper = true
        helperResult = nil
        Task {
            do {
                let message = try await spoolHelperService.testConnection()
                helperResult = .success(message)
            } catch {
                helperResult = .failure(error.localizedDescription)
            }
            testingHelper = false
        }
    }

    private func checkMissingFields() {
        checkingFields = true
        Task {
            do {
                let missing = try await spoolmanService.missingExtraFields()
                if missing.isEmpty {
                    fieldsResultTitle = "All Fields Exist"
                    fieldsResultMessage = "All custom fields are already configured in Spoolman."
                    showFieldsResult = true
                } else {
                    missingFields = missing
                    showFieldsConfirmation = true
                }
            } catch {
                fieldsResultTitle = "Error"
                fieldsResultMessage = error.localizedDescription
                showFieldsResult = true
            }
            checkingFields = false
            await spoolmanService.checkExtraFields()
        }
    }

    private func createFields() {
        checkingFields = true
        Task {
            do {
                try await spoolmanService.ensureExtraFields()
                fieldsResultTitle = "Fields Created"
                fieldsResultMessage = "All custom fields have been created successfully."
            } catch {
                fieldsResultTitle = "Error"
                fieldsResultMessage = error.localizedDescription
            }
            checkingFields = false
            showFieldsResult = true
            await spoolmanService.checkExtraFields()
        }
    }
}
