import SwiftUI

struct SpoolDetailView: View {
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService
    var labelPrinterService: LabelPrinterService

    @State private var spool: Spool
    @State private var nfcWriter = NFCWriter()
    @State private var showNFCAlert = false
    @State private var nfcAlertTitle = ""
    @State private var nfcAlertMessage = ""
    @State private var showTrayPicker = false
    @State private var showHelperAlert = false
    @State private var helperAlertTitle = ""
    @State private var helperAlertMessage = ""
    @State private var isSendingToHelper = false
    @State private var showProfilePicker = false
    @State private var isUnlinking = false
    @State private var showLabelPreview = false
    @AppStorage("spoolmanURL") private var spoolmanURL = ""

    init(spool: Spool, spoolmanService: SpoolmanService, spoolHelperService: SpoolHelperService, labelPrinterService: LabelPrinterService) {
        self._spool = State(initialValue: spool)
        self.spoolmanService = spoolmanService
        self.spoolHelperService = spoolHelperService
        self.labelPrinterService = labelPrinterService
    }

    var body: some View {
        List {
            // Color & Name header
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color(hex: spool.colorHex) ?? .gray)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(spool.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let vendor = spool.vendorName {
                            Text(vendor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Details
            Section("Details") {
                if let material = spool.materialName {
                    LabeledContent("Material", value: material)
                }
                if let remaining = spool.remainingWeight {
                    LabeledContent("Remaining", value: "\(Int(remaining))g")
                }
                if let used = spool.usedWeight {
                    LabeledContent("Used", value: String(format: "%.1fg", used))
                }
                if let filament = spool.filament {
                    LabeledContent("Filament", value: "#\(filament.id) \(filament.displayName)")
                }
                if let location = spool.location, !location.isEmpty {
                    LabeledContent("Location", value: location)
                }
                if let lotNr = spool.lotNr, !lotNr.isEmpty {
                    LabeledContent("Lot Number", value: lotNr)
                }
                if let comment = spool.comment, !comment.isEmpty {
                    LabeledContent("Comment", value: comment)
                }
            }

            Section("Parameters") {
                let params = spool.customParameters
                if let temp = params.nozzleTemp {
                    LabeledContent("Nozzle Temp", value: temp)
                }
                if let temp = params.bedTemp {
                    LabeledContent("Bed Temp", value: temp)
                }
                if let speed = params.printSpeed {
                    LabeledContent("Print Speed", value: speed)
                }
                if let drying = params.drying {
                    LabeledContent("Drying", value: drying)
                }
            }

            // Bambu Link Status
            Section("BambuStudio Profile") {
                if let info = spool.customInfo {
                    LabeledContent("Filament ID", value: info.trayInfoIdx)
                    LabeledContent("Setting ID", value: info.settingId)
                    LabeledContent("Type", value: info.trayType)

                    Button {
                        unlinkProfile()
                    } label: {
                        HStack {
                            Label("Unlink Profile", systemImage: "link.badge.plus")
                            if isUnlinking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isUnlinking)

                    if spoolHelperService.isAvailable && spool.customInfo != nil {
                        Button {
                            showTrayPicker = true
                        } label: {
                            HStack {
                                Label("Set in BambuStudio", systemImage: "desktopcomputer")
                                if isSendingToHelper {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSendingToHelper)
                    }
                } else {
                    Button {
                        showProfilePicker = true
                    } label: {
                        Label("Link to BambuStudio Profile", systemImage: "link.badge.plus")
                    }
                }
            }

            // Actions
            Section {
                Button {
                    showLabelPreview = true
                } label: {
                    Label("Print Label", systemImage: "printer")
                }

                Button {
                    writeNFCTag()
                } label: {
                    Label("Write NFC Tag", systemImage: "wave.3.right")
                }
            }
        }
        .alert(nfcAlertTitle, isPresented: $showNFCAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nfcAlertMessage)
        }
        .alert(helperAlertTitle, isPresented: $showHelperAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helperAlertMessage)
        }
        .sheet(isPresented: $showProfilePicker) {
            if let filamentId = spool.filament?.id {
                ProfilePickerSheet(
                    filamentId: filamentId,
                    spoolmanService: spoolmanService,
                    spoolHelperService: spoolHelperService,
                    onLinked: { refreshSpool() }
                )
            }
        }
        .sheet(isPresented: $showLabelPreview) {
            LabelPreviewSheet(
                spool: spool,
                spoolmanURL: spoolmanURL,
                labelPrinterService: labelPrinterService
            )
        }
        .confirmationDialog("Select Tray", isPresented: $showTrayPicker) {
            ForEach(0..<4) { tray in
                Button("Tray \(tray + 1)") {
                    sendToHelper(tray: tray)
                }
            }
            Button("External Tray") {
                sendToHelper(tray: 4)
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Spool #\(spool.id)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func unlinkProfile() {
        guard let filamentId = spool.filament?.id else { return }
        isUnlinking = true
        Task {
            do {
                try await spoolmanService.unlinkFilament(id: filamentId)
                refreshSpool()
            } catch {
                helperAlertTitle = "Error"
                helperAlertMessage = error.localizedDescription
                showHelperAlert = true
            }
            isUnlinking = false
        }
    }

    private func refreshSpool() {
        Task {
            if let updated = try? await spoolmanService.fetchSpool(id: spool.id) {
                spool = updated
            }
        }
    }

    private func sendToHelper(tray: Int) {
        isSendingToHelper = true
        Task {
            do {
                let result = try await spoolHelperService.activate(spool: spool, tray: tray)
                helperAlertTitle = "Profile Activated"
                helperAlertMessage = result.message
            } catch {
                helperAlertTitle = "Error"
                helperAlertMessage = error.localizedDescription
            }
            isSendingToHelper = false
            showHelperAlert = true
        }
    }

    private func writeNFCTag() {
        guard let url = URL(string: "spoolbrowser://spool/\(spool.id)") else { return }
        nfcWriter.write(url: url) { result in
            MainActor.assumeIsolated {
                switch result {
                case .success:
                    nfcAlertTitle = "Success"
                    nfcAlertMessage = "Spool URL written to NFC tag."
                    showNFCAlert = true
                case .failure(let error):
                    if let nfcError = error as? NFCWriter.NFCWriteError,
                       case .sessionInvalidated = nfcError {
                        return
                    }
                    nfcAlertTitle = "Error"
                    nfcAlertMessage = error.localizedDescription
                    showNFCAlert = true
                }
            }
        }
    }
}
