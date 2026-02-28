import Foundation

struct Vendor: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case comment
    }
}
