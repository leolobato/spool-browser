import Foundation

struct Spool: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let filament: Filament?
    let remainingWeight: Double?
    let usedWeight: Double?
    let remainingLength: Double?
    let usedLength: Double?
    let location: String?
    let comment: String?
    let lotNr: String?
    let registeredDate: String?
    let firstUsedDate: String?
    let lastUsedDate: String?
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case filament
        case remainingWeight = "remaining_weight"
        case usedWeight = "used_weight"
        case remainingLength = "remaining_length"
        case usedLength = "used_length"
        case location
        case comment
        case lotNr = "lot_nr"
        case registeredDate = "registered"
        case firstUsedDate = "first_used"
        case lastUsedDate = "last_used"
        case archived
    }

    var displayName: String {
        filament?.displayName ?? "Unknown Spool"
    }

    var vendorName: String? {
        filament?.vendor?.name
    }

    var materialName: String? {
        filament?.material
    }

    var colorHex: String? {
        filament?.colorHex
    }

    var customInfo: CustomFilamentInfo? {
        guard let filament else { return nil }
        return CustomFilamentInfo(filament: filament)
    }
}
