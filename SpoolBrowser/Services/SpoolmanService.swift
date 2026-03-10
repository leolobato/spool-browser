import Foundation
import Observation

@Observable
@MainActor
final class SpoolmanService {
    private(set) var isConfigured = false
    private(set) var isConnected = false
    private(set) var extraFieldsStatus: ExtraFieldsStatus = .unknown
    private var baseURL: URL?

    enum ExtraFieldsStatus {
        case unknown
        case checking
        case allPresent
        case missing(Int)
        case error

        var isAllPresent: Bool {
            if case .allPresent = self { return true }
            return false
        }
    }

    func configure(baseURL urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed) else {
            self.baseURL = nil
            self.isConfigured = false
            self.isConnected = false
            return
        }
        self.baseURL = url
        self.isConfigured = true
        self.isConnected = false
    }

    func checkConnection() async {
        guard isConfigured else {
            isConnected = false
            return
        }
        do {
            try await testConnection()
            isConnected = true
        } catch {
            isConnected = false
        }
    }

    func fetchSpools() async throws -> [Spool] {
        let data = try await get(path: "/api/v1/spool")
        let decoder = JSONDecoder()
        return try decoder.decode([Spool].self, from: data)
    }

    func fetchSpool(id: Int) async throws -> Spool {
        let data = try await get(path: "/api/v1/spool/\(id)")
        let decoder = JSONDecoder()
        return try decoder.decode(Spool.self, from: data)
    }

    func fetchFilament(id: Int) async throws -> Filament {
        let data = try await get(path: "/api/v1/filament/\(id)")
        let decoder = JSONDecoder()
        return try decoder.decode(Filament.self, from: data)
    }

    func updateSpoolLocation(id: Int, location: String) async throws {
        guard let baseURL else { throw SpoolmanError.notConfigured }
        let url = baseURL.appendingPathComponent("/api/v1/spool/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["location": location]
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SpoolmanError.requestFailed
        }
    }

    func testConnection() async throws {
        _ = try await get(path: "/api/v1/health")
    }

    // MARK: - Filament Profile Linking

    func linkFilament(id: Int, profile: FilamentProfile) async throws {
        let extra: [String: String] = [
            "ams_filament_id": encodeText(profile.filamentId),
            "ams_filament_type": encodeText(profile.filamentType),
            "nozzle_temp": encodeRange(profile.nozzleTempMin, profile.nozzleTempMax),
            "bed_temp": encodeRange(profile.bedTempMin, profile.bedTempMax),
            "drying_temperature": encodeRange(profile.dryingTempMin, profile.dryingTempMax),
            "drying_time": encodeInt(profile.dryingTime),
            "printing_speed": encodeRange(profile.printSpeedMin, profile.printSpeedMax),
        ]
        try await patchFilamentExtra(id: id, extra: extra)
    }

    func linkFilamentManual(
        id: Int,
        amsFilamentId: String,
        nozzleTempMin: Int,
        nozzleTempMax: Int,
        filamentType: String
    ) async throws {
        let extra: [String: String] = [
            "ams_filament_id": encodeText(amsFilamentId),
            "ams_filament_type": encodeText(filamentType),
            "nozzle_temp": encodeRange(nozzleTempMin, nozzleTempMax),
        ]
        try await patchFilamentExtra(id: id, extra: extra)
    }

    func unlinkFilament(id: Int) async throws {
        let extra: [String: Any] = [
            "ams_filament_id": NSNull(),
            "ams_filament_type": NSNull(),
            "nozzle_temp": NSNull(),
            "bed_temp": NSNull(),
            "drying_temperature": NSNull(),
            "drying_time": NSNull(),
            "printing_speed": NSNull(),
        ]
        try await patchFilamentExtra(id: id, extra: extra)
    }

    static let requiredExtraFields: [(key: String, name: String, fieldType: String, unit: String?)] = [
        ("ams_filament_id", "AMS Filament ID", "text", nil),
        ("ams_filament_type", "AMS Filament Type", "text", nil),
        ("nozzle_temp", "Nozzle Temperature", "integer_range", "\u{00B0}C"),
        ("bed_temp", "Bed Temperature", "integer_range", "\u{00B0}C"),
        ("drying_temperature", "Drying Temperature", "integer_range", "\u{00B0}C"),
        ("drying_time", "Drying Time", "integer", "h"),
        ("printing_speed", "Printing Speed", "integer_range", "mm/s"),
    ]

    func missingExtraFields() async throws -> [String] {
        let existingKeys = try await fetchExistingFieldKeys()
        return Self.requiredExtraFields
            .filter { !existingKeys.contains($0.key) }
            .map(\.name)
    }

    func checkExtraFields() async {
        guard isConfigured else {
            extraFieldsStatus = .unknown
            return
        }
        extraFieldsStatus = .checking
        do {
            let missing = try await missingExtraFields()
            if missing.isEmpty {
                extraFieldsStatus = .allPresent
            } else {
                extraFieldsStatus = .missing(missing.count)
            }
        } catch {
            extraFieldsStatus = .error
        }
    }

    func ensureExtraFields() async throws {
        let existingKeys = try await fetchExistingFieldKeys()

        for field in Self.requiredExtraFields where !existingKeys.contains(field.key) {
            try await postExtraField(key: field.key, name: field.name, fieldType: field.fieldType, unit: field.unit)
        }
    }

    // MARK: - Value Encoding

    /// Encodes a text value for Spoolman extra fields (JSON-quoted string).
    private func encodeText(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value) {
            return String(data: data, encoding: .utf8) ?? value
        }
        return value
    }

    /// Encodes an integer_range value as "[min, max]".
    private func encodeRange(_ min: Int, _ max: Int) -> String {
        "[\(min), \(max)]"
    }

    /// Encodes an integer value as a plain number string.
    private func encodeInt(_ value: Int) -> String {
        String(value)
    }

    // MARK: - Private

    /// PATCHes extra fields on a filament. Values must be pre-formatted
    /// in Spoolman's expected format (JSON-encoded text, integer_range, or integer).
    private func patchFilamentExtra(id: Int, extra: [String: Any]) async throws {
        guard let baseURL else { throw SpoolmanError.notConfigured }
        let url = baseURL.appendingPathComponent("/api/v1/filament/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["extra": extra]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SpoolmanError.requestFailed
        }
    }

    private func fetchExistingFieldKeys() async throws -> Set<String> {
        let data = try await get(path: "/api/v1/field/filament")
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SpoolmanError.requestFailed
        }
        return Set(fields.compactMap { $0["key"] as? String })
    }

    private func postExtraField(key: String, name: String, fieldType: String, unit: String?) async throws {
        guard let baseURL else { throw SpoolmanError.notConfigured }
        let url = baseURL.appendingPathComponent("/api/v1/field/filament/\(key)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["name": name, "field_type": fieldType]
        if let unit { body["unit"] = unit }
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SpoolmanError.requestFailed
        }
    }

    private func get(path: String) async throws -> Data {
        guard let baseURL else { throw SpoolmanError.notConfigured }
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SpoolmanError.requestFailed
        }
        return data
    }
}

enum SpoolmanError: LocalizedError {
    case notConfigured
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Spoolman URL not configured. Please set it in Settings."
        case .requestFailed:
            "Spoolman request failed. Check your URL and try again."
        }
    }
}
