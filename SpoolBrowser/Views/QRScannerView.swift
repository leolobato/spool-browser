import SwiftUI
import AVFoundation
import VisionKit

struct QRScannerView: View {
    var spoolmanService: SpoolmanService
    @Binding var selectedTab: AppTab
    @Binding var navigationPath: NavigationPath

    @State private var nfcReader = NFCReader()
    @State private var alertMessage: String?
    @State private var isShowingAlert = false
    @State private var isLoading = false
    @State private var isCameraAuthorized: Bool?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if !DataScannerViewController.isSupported {
                    ContentUnavailableView(
                        "Scanner Not Available",
                        systemImage: "camera.viewfinder",
                        description: Text("This device doesn't support barcode scanning.")
                    )
                } else if isCameraAuthorized == false {
                    ContentUnavailableView {
                        Label("Camera Access Needed", systemImage: "camera.viewfinder")
                    } description: {
                        Text("Allow camera access in Settings to scan spool labels.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } else if isCameraAuthorized == true {
                    DataScannerRepresentable(
                        isActive: selectedTab == .scan && scenePhase == .active
                    ) { code in
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()

                    if isLoading {
                        ProgressView("Loading spool...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }

                if DataScannerViewController.isSupported && isCameraAuthorized == true && !isLoading {
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
            .task {
                await updateCameraAuthorization()
            }
        }
    }

    private func updateCameraAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
        case .notDetermined:
            isCameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isCameraAuthorized = false
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
    var isActive: Bool
    var onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerHostViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return ScannerHostViewController(scanner: scanner)
    }

    func updateUIViewController(_ uiViewController: ScannerHostViewController, context: Context) {
        uiViewController.isActive = isActive
    }

    static func dismantleUIViewController(_ uiViewController: ScannerHostViewController, coordinator: Coordinator) {
        uiViewController.isActive = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    final class ScannerHostViewController: UIViewController {
        let scanner: DataScannerViewController
        private var isViewVisible = false
        private var retryTask: Task<Void, Never>?

        // Scanning is restarted on the same scanner instance rather than
        // recreating the controller: a second DataScannerViewController can't
        // start while the previous one still holds the camera.
        var isActive = false {
            didSet {
                guard isActive != oldValue else { return }
                updateScanningState()
            }
        }

        init(scanner: DataScannerViewController) {
            self.scanner = scanner
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isViewVisible = true
            updateScanningState()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isViewVisible = false
            updateScanningState()
        }

        private func updateScanningState() {
            retryTask?.cancel()
            retryTask = nil
            if isActive && isViewVisible {
                startScanning(attempt: 0)
            } else if scanner.isScanning {
                scanner.stopScanning()
            }
        }

        private func startScanning(attempt: Int) {
            guard isActive, isViewVisible, !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                // The camera can be briefly unavailable (right after boot, or
                // while a previous capture session is tearing down) — retry.
                guard attempt < 20 else {
                    print("DataScannerViewController.startScanning failed: \(error)")
                    return
                }
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.startScanning(attempt: attempt + 1)
                }
            }
        }
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

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove items: [RecognizedItem], allItems: [RecognizedItem]) {
            // Allow rescanning the same code once it leaves the frame.
            for item in items {
                if case .barcode(let barcode) = item,
                   barcode.payloadStringValue == lastScannedCode {
                    lastScannedCode = nil
                }
            }
        }
    }
}
