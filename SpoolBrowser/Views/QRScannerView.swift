import SwiftUI
import VisionKit

struct QRScannerView: View {
    var spoolmanService: SpoolmanService
    @Binding var selectedTab: AppTab
    @Binding var navigationPath: NavigationPath

    @State private var nfcReader = NFCReader()
    @State private var alertMessage: String?
    @State private var isShowingAlert = false
    @State private var isLoading = false
    @State private var scannerResetID = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable { code in
                        handleScannedCode(code)
                    }
                    .id(scannerResetID)
                    .ignoresSafeArea()

                    if isLoading {
                        ProgressView("Loading spool...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                } else {
                    ContentUnavailableView(
                        "Scanner Not Available",
                        systemImage: "camera.viewfinder",
                        description: Text("This device doesn't support barcode scanning.")
                    )
                }

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable && !isLoading {
                    Button {
                        readNFC()
                    } label: {
                        Label("Read NFC", systemImage: "wave.3.right")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Scan")
            .alert("Scan Error", isPresented: $isShowingAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "An unknown error occurred.")
            }
            .onChange(of: selectedTab) { _, newValue in
                if newValue == .scan && !isLoading {
                    scannerResetID = UUID()
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        guard !isLoading else { return }
        guard let url = URL(string: code) else {
            showAlert("Invalid QR code content.")
            return
        }

        // Match Spoolman web URL: /spool/show/{id}
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 3,
              pathComponents[pathComponents.count - 3] == "spool",
              pathComponents[pathComponents.count - 2] == "show",
              let spoolId = Int(pathComponents[pathComponents.count - 1]) else {
            showAlert("QR code doesn't contain a Spoolman spool URL.")
            return
        }

        navigateToSpool(id: spoolId)
    }

    private func readNFC() {
        guard !isLoading else { return }
        nfcReader.read { result in
            MainActor.assumeIsolated {
                switch result {
                case .success(let url):
                    guard let deepLink = DeepLinkHandler.parse(url: url),
                          case .spool(let id) = deepLink else {
                        showAlert("NFC tag doesn't contain a valid spool URL.")
                        return
                    }
                    navigateToSpool(id: id)
                case .failure(let error):
                    if error is NFCReader.NFCReadError,
                       case .sessionCancelled = error as! NFCReader.NFCReadError {
                        return
                    }
                    showAlert(error.localizedDescription)
                }
            }
        }
    }

    private func navigateToSpool(id: Int) {
        isLoading = true
        Task {
            do {
                let spool = try await spoolmanService.fetchSpool(id: id)
                navigationPath = NavigationPath()
                selectedTab = .spools
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigationPath.append(spool)
                    isLoading = false
                }
            } catch {
                showAlert("Failed to load spool: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCodeScanned: (String) -> Void
        private var lastScannedCode: String?

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let item = items.first,
                  case .barcode(let barcode) = item,
                  let value = barcode.payloadStringValue,
                  value != lastScannedCode else { return }
            lastScannedCode = value
            onCodeScanned(value)
        }
    }
}
