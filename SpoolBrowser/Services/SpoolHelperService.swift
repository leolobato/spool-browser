import Foundation

@Observable
@MainActor
final class SpoolHelperService {
    var manualAddress: String = "" {
        didSet { UserDefaults.standard.set(manualAddress, forKey: "spoolHelperAddress") }
    }

    var isAvailable: Bool {
        !effectiveAddress.isEmpty
    }

    private var effectiveAddress: String {
        let trimmed = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http") { return trimmed }
        return "http://\(trimmed)"
    }

    init() {
        manualAddress = UserDefaults.standard.string(forKey: "spoolHelperAddress") ?? ""
    }

    func activate(spool: Spool, tray: Int) async throws -> ActivationResult {
        guard let info = spool.customInfo else {
            throw SpoolHelperError.notLinked
        }

        let base = effectiveAddress
        guard !base.isEmpty, let url = URL(string: "\(base)/activate") else {
            throw SpoolHelperError.notAvailable
        }

        var body: [String: Any] = [
            "filament_id": info.amsFilamentId,
            "filament_type": info.trayType,
            "color_hex": spool.colorHex ?? "",
            "tray": tray,
        ]
        if let nozzleTempMin = info.nozzleTempMin {
            body["nozzle_temp_min"] = nozzleTempMin
        }
        if let nozzleTempMax = info.nozzleTempMax {
            body["nozzle_temp_max"] = nozzleTempMax
        }
        if let bedTempMin = info.bedTempMin {
            body["bed_temp"] = bedTempMin
        }

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

    func fetchProfiles(search: String = "") async throws -> [FilamentProfile] {
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
        return try JSONDecoder().decode([FilamentProfile].self, from: data)
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
            "bambu-spool-helper is not available on the network."
        case .notLinked:
            "This spool is not linked to a slicer profile."
        case .requestFailed:
            "Failed to communicate with bambu-spool-helper."
        case .activationFailed(let message):
            message
        }
    }
}
