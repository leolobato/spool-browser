import Foundation

struct CustomFilamentInfo: Sendable {
    let amsFilamentId: String
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
        amsFilamentId: String,
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
        self.amsFilamentId = amsFilamentId
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

        let amsFilamentId = Self.extractText(extra, key: "ams_filament_id") ?? ""
        let filamentType = Self.extractText(extra, key: "ams_filament_type")
            ?? filament.material
            ?? ""

        // Keep linked-state semantics aligned with spool-helper.
        guard !amsFilamentId.isEmpty else { return nil }

        self.amsFilamentId = amsFilamentId
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

    // MARK: - Tray Type Validation

    /// Valid tray_type values accepted by the Bambu Lab AMS ams_filament_setting MQTT command.
    /// Sourced from BambuStudio PrintConfig.cpp filament_type enum plus firmware support aliases.
    static let validTrayTypes: Set<String> = [
        "PLA", "ABS", "ASA", "ASA-CF", "PETG", "PCTG",
        "TPU", "TPU-AMS", "PC",
        "PA", "PA-CF", "PA-GF", "PA6-CF",
        "PLA-CF", "PET-CF", "PETG-CF",
        "PVA", "HIPS",
        "PLA-AERO", "PPS", "PPS-CF",
        "PPA-CF", "PPA-GF", "ABS-GF", "ASA-AERO",
        "PE", "PP", "EVA", "PHA", "BVOH",
        "PE-CF", "PP-CF", "PP-GF",
        // Firmware support-material aliases
        "PLA-S", "PA-S", "ABS-S",
    ]

    /// Whether `trayType` is a value the AMS firmware accepts.
    var hasValidTrayType: Bool {
        Self.validTrayTypes.contains(trayType.uppercased())
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
