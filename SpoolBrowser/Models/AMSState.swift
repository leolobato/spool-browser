import Foundation

/// Snapshot of the AMS + external spool served by bambu-spool-helper's `GET /ams`.
struct AMSState: Codable, Sendable {
    let connected: Bool
    let printerState: String?
    let activeTray: Int?
    let trays: [AMSTray]

    enum CodingKeys: String, CodingKey {
        case connected
        case printerState = "printer_state"
        case activeTray = "active_tray"
        case trays
    }
}

struct AMSTray: Codable, Sendable, Identifiable, Hashable {
    /// Helper tray index: 0–3 = AMS slots A1–A4, 4 = external spool.
    let tray: Int
    let label: String
    let empty: Bool
    let trayType: String
    let trayColor: String
    let filamentId: String
    let traySubBrands: String
    /// AMS-reported remaining percentage; -1 when unknown.
    let remain: Int
    let nozzleTempMin: Int
    let nozzleTempMax: Int
    let bedTemp: Int
    /// Bound Spoolman spool id, when the helper could resolve one.
    let spoolId: Int?

    var id: Int { tray }

    var isExternal: Bool { tray == AMSTray.externalTrayIndex }

    static let externalTrayIndex = 4

    enum CodingKeys: String, CodingKey {
        case tray
        case label
        case empty
        case trayType = "tray_type"
        case trayColor = "tray_color"
        case filamentId = "filament_id"
        case traySubBrands = "tray_sub_brands"
        case remain
        case nozzleTempMin = "nozzle_temp_min"
        case nozzleTempMax = "nozzle_temp_max"
        case bedTemp = "bed_temp"
        case spoolId = "spool_id"
    }
}
