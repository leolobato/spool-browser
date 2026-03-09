import Foundation

struct FilamentProfile: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let filamentId: String
    let trayInfoIdx: String
    let filamentType: String
    let nozzleTempMin: Int
    let nozzleTempMax: Int
    let bedTempMin: Int
    let bedTempMax: Int
    let dryingTempMin: Int
    let dryingTempMax: Int
    let dryingTime: Int
    let printSpeedMin: Int
    let printSpeedMax: Int
    let source: String

    var id: String { "\(filamentId)-\(trayInfoIdx)" }

    enum CodingKeys: String, CodingKey {
        case name, source
        case filamentId = "filament_id"
        case trayInfoIdx = "tray_info_idx"
        case filamentType = "filament_type"
        case nozzleTempMin = "nozzle_temp_min"
        case nozzleTempMax = "nozzle_temp_max"
        case bedTempMin = "bed_temp_min"
        case bedTempMax = "bed_temp_max"
        case dryingTempMin = "drying_temp_min"
        case dryingTempMax = "drying_temp_max"
        case dryingTime = "drying_time"
        case printSpeedMin = "print_speed_min"
        case printSpeedMax = "print_speed_max"
    }
}
