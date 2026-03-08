import Foundation
import Network

@Observable
@MainActor
final class SpoolHelperService {
    private(set) var isDiscovered = false
    private(set) var discoveredName: String?

    var manualAddress: String = "" {
        didSet { UserDefaults.standard.set(manualAddress, forKey: "spoolHelperAddress") }
    }

    var isAvailable: Bool {
        isDiscovered || !effectiveAddress.isEmpty
    }

    private var browser: NWBrowser?
    private var resolvedHost: String?
    private var resolvedPort: UInt16?
    private var resolveConnection: NWConnection?

    private var effectiveAddress: String {
        if let host = resolvedHost, let port = resolvedPort {
            return "http://\(host):\(port)"
        }
        let trimmed = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if trimmed.hasPrefix("http") { return trimmed }
            return "http://\(trimmed)"
        }
        return ""
    }

    init() {
        manualAddress = UserDefaults.standard.string(forKey: "spoolHelperAddress") ?? ""
    }

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_spoolhelper._tcp", domain: nil), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                if let result = results.first {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.discoveredName = name
                    }
                    self.isDiscovered = true
                    self.resolveEndpoint(result.endpoint)
                } else {
                    self.isDiscovered = false
                    self.discoveredName = nil
                    self.resolvedHost = nil
                    self.resolvedPort = nil
                    self.resolveConnection?.cancel()
                    self.resolveConnection = nil
                }
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    self?.isDiscovered = false
                }
            }
        }

        self.browser = browser
        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        resolveConnection?.cancel()
        resolveConnection = nil
        isDiscovered = false
        discoveredName = nil
        resolvedHost = nil
        resolvedPort = nil
    }

    func activate(spool: Spool, tray: Int) async throws -> ActivationResult {
        guard let info = spool.customInfo else {
            throw SpoolHelperError.notLinked
        }

        let base = effectiveAddress
        guard !base.isEmpty, let url = URL(string: "\(base)/activate") else {
            throw SpoolHelperError.notAvailable
        }

        let body: [String: Any] = [
            "setting_id": info.settingId,
            "filament_id": info.trayInfoIdx,
            "color_hex": spool.colorHex ?? "",
            "tray": tray,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard response is HTTPURLResponse else {
            throw SpoolHelperError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpoolHelperError.requestFailed
        }

        let success = json["success"] as? Bool ?? false
        let profileName = json["profile_name"] as? String ?? ""
        let message = json["message"] as? String ?? ""

        if success {
            return ActivationResult(profileName: profileName, message: message)
        } else {
            throw SpoolHelperError.activationFailed(message)
        }
    }

    func fetchProfiles(search: String = "") async throws -> [BambuProfile] {
        let base = effectiveAddress
        var urlString = "\(base)/profiles"
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let encoded = trimmedSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedSearch
            urlString += "?search=\(encoded)"
        }
        guard !base.isEmpty, let url = URL(string: urlString) else {
            throw SpoolHelperError.notAvailable
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([BambuProfile].self, from: data)
    }

    func testConnection() async throws -> String {
        let base = effectiveAddress
        guard !base.isEmpty, let url = URL(string: "\(base)/status") else {
            throw SpoolHelperError.notAvailable
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileCount = json["profiles_loaded"] as? Int
        else {
            throw SpoolHelperError.requestFailed
        }
        return "\(profileCount) profiles loaded"
    }

    // MARK: - Endpoint resolution

    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        resolveConnection?.cancel()
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolveConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4:
                        hostString = "\(host)"
                    case .ipv6:
                        hostString = "[\(host)]"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        hostString = "\(host)"
                    }
                    Task { @MainActor in
                        self?.resolvedHost = hostString
                        self?.resolvedPort = port.rawValue
                    }
                }
                connection.cancel()
            case .failed:
                connection.cancel()
                Task { @MainActor in
                    self?.resolveConnection = nil
                }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
}

struct ActivationResult: Sendable {
    let profileName: String
    let message: String
}

enum SpoolHelperError: LocalizedError {
    case notAvailable
    case notLinked
    case requestFailed
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "SpoolHelper is not available on the network."
        case .notLinked:
            "This spool is not linked to a slicer profile."
        case .requestFailed:
            "Failed to communicate with SpoolHelper."
        case .activationFailed(let message):
            message
        }
    }
}
