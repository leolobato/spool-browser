import Foundation

struct Filament: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String?
    let vendor: Vendor?
    let material: String?
    let density: Double?
    let diameter: Double?
    let weight: Double?
    let spoolWeight: Double?
    let colorHex: String?
    let settingsExtruderTemp: Int?
    let settingsBedTemp: Int?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case vendor
        case material
        case density
        case diameter
        case weight
        case spoolWeight = "spool_weight"
        case colorHex = "color_hex"
        case settingsExtruderTemp = "settings_extruder_temp"
        case settingsBedTemp = "settings_bed_temp"
        case extra
    }

    var displayName: String {
        name ?? "Unknown Filament"
    }
}
