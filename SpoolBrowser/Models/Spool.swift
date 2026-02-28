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

    struct CustomParameters {
        let nozzleTemp: String?
        let bedTemp: String?
        let printSpeed: String?
        let drying: String?

        init(filament: Filament?) {
            let extra = filament?.extra

            if let range = Self.extractRange(extra, key: "nozzle_temp") {
                nozzleTemp = Self.formatRange(range.0, range.1, unit: "\u{00B0}C")
            } else if let temp = filament?.settingsExtruderTemp {
                nozzleTemp = "\(temp)\u{00B0}C"
            } else {
                nozzleTemp = nil
            }

            if let range = Self.extractRange(extra, key: "bed_temp") {
                bedTemp = Self.formatRange(range.0, range.1, unit: "\u{00B0}C")
            } else if let temp = filament?.settingsBedTemp {
                bedTemp = "\(temp)\u{00B0}C"
            } else {
                bedTemp = nil
            }

            if let range = Self.extractRange(extra, key: "printing_speed") {
                printSpeed = Self.formatRange(range.0, range.1, unit: "mm/s")
            } else {
                printSpeed = nil
            }

            let tempRange = Self.extractRange(extra, key: "drying_temperature")
            let dryingTime = extra?["drying_time"].flatMap { Int($0) }
            switch (tempRange, dryingTime) {
            case let (range?, time?):
                drying = "\(Self.formatRange(range.0, range.1, unit: "\u{00B0}C")) / \(time)h"
            case let (range?, nil):
                drying = Self.formatRange(range.0, range.1, unit: "\u{00B0}C")
            case let (nil, time?):
                drying = "\(time)h"
            case (nil, nil):
                drying = nil
            }
        }

        private static func extractRange(_ extra: [String: String]?, key: String) -> (Int, Int)? {
            guard let value = extra?[key], !value.isEmpty,
                  let data = value.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Int].self, from: data),
                  arr.count == 2
            else { return nil }
            return (arr[0], arr[1])
        }

        private static func formatRange(_ min: Int, _ max: Int, unit: String) -> String {
            if min == max { return "\(min) \(unit)" }
            return "\(min)-\(max) \(unit)"
        }
    }

    var customParameters: CustomParameters {
        CustomParameters(filament: filament)
    }
}
