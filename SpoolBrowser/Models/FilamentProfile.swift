import Foundation

struct FilamentProfile: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let filamentId: String
    let settingId: String
    let filamentType: String
    let nozzleTempMin: Int
    let nozzleTempMax: Int
    let bedTempMin: Int
    let bedTempMax: Int
    let source: String

    var id: String { "\(settingId)-\(filamentId)" }

    enum CodingKeys: String, CodingKey {
        case name, source
        case filamentId = "filament_id"
        case settingId = "setting_id"
        case filamentType = "filament_type"
        case nozzleTempMin = "nozzle_temp_min"
        case nozzleTempMax = "nozzle_temp_max"
        case bedTempMin = "bed_temp_min"
        case bedTempMax = "bed_temp_max"
    }
}
