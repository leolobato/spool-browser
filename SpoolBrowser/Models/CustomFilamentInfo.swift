import Foundation

struct CustomFilamentInfo: Sendable {
    let trayInfoIdx: String
    let settingId: String
    let nozzleTempMin: Int?
    let nozzleTempMax: Int?
    let trayType: String
    let bedTempMin: Int?
    let bedTempMax: Int?
    let dryingTempMin: Int?
    let dryingTempMax: Int?
    let dryingTime: Int?
    let printSpeedMin: Int?
    let printSpeedMax: Int?

    init(
        trayInfoIdx: String,
        settingId: String,
        nozzleTempMin: Int? = nil,
        nozzleTempMax: Int? = nil,
        trayType: String = "",
        bedTempMin: Int? = nil,
        bedTempMax: Int? = nil,
        dryingTempMin: Int? = nil,
        dryingTempMax: Int? = nil,
        dryingTime: Int? = nil,
        printSpeedMin: Int? = nil,
        printSpeedMax: Int? = nil
    ) {
        self.trayInfoIdx = trayInfoIdx
        self.settingId = settingId
        self.nozzleTempMin = nozzleTempMin
        self.nozzleTempMax = nozzleTempMax
        self.trayType = trayType
        self.bedTempMin = bedTempMin
        self.bedTempMax = bedTempMax
        self.dryingTempMin = dryingTempMin
        self.dryingTempMax = dryingTempMax
        self.dryingTime = dryingTime
        self.printSpeedMin = printSpeedMin
        self.printSpeedMax = printSpeedMax
    }

    init?(filament: Filament) {
        guard let extra = filament.extra else { return nil }

        let filamentId = Self.extractText(extra, key: "bambu_filament_id") ?? ""
        let settingId = Self.extractText(extra, key: "bambu_setting_id") ?? ""
        let filamentType = Self.extractText(extra, key: "bambu_filament_type")
            ?? filament.material
            ?? ""

        // Keep linked-state semantics aligned with spool-helper.
        guard !filamentId.isEmpty || !settingId.isEmpty else { return nil }

        self.trayInfoIdx = filamentId
        self.settingId = settingId
        self.trayType = filamentType
        if let nozzleRange = Self.extractRange(extra, key: "nozzle_temp") {
            self.nozzleTempMin = nozzleRange.0
            self.nozzleTempMax = nozzleRange.1
        } else if let temp = filament.settingsExtruderTemp {
            self.nozzleTempMin = temp
            self.nozzleTempMax = temp
        } else {
            self.nozzleTempMin = nil
            self.nozzleTempMax = nil
        }

        if let range = Self.extractRange(extra, key: "bed_temp") {
            self.bedTempMin = range.0
            self.bedTempMax = range.1
        } else {
            self.bedTempMin = nil
            self.bedTempMax = nil
        }
        if let range = Self.extractRange(extra, key: "drying_temperature") {
            self.dryingTempMin = range.0
            self.dryingTempMax = range.1
        } else {
            self.dryingTempMin = nil
            self.dryingTempMax = nil
        }
        self.dryingTime = Self.extractInt(extra, key: "drying_time")
        if let range = Self.extractRange(extra, key: "printing_speed") {
            self.printSpeedMin = range.0
            self.printSpeedMax = range.1
        } else {
            self.printSpeedMin = nil
            self.printSpeedMax = nil
        }
    }

    // MARK: - Field Parsing

    /// Extracts a text field value. Spoolman stores text as JSON-quoted strings.
    private static func extractText(_ extra: [String: String], key: String) -> String? {
        guard let value = extra[key], !value.isEmpty else { return nil }
        if value.hasPrefix("\"") && value.hasSuffix("\""),
           let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return value
    }

    /// Extracts an integer_range field stored as "[min, max]".
    private static func extractRange(_ extra: [String: String], key: String) -> (Int, Int)? {
        guard let value = extra[key], !value.isEmpty,
              let data = value.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Int].self, from: data),
              arr.count == 2
        else { return nil }
        return (arr[0], arr[1])
    }

    /// Extracts an integer field stored as a plain number string.
    private static func extractInt(_ extra: [String: String], key: String) -> Int? {
        guard let value = extra[key], !value.isEmpty else { return nil }
        return Int(value)
    }
}
