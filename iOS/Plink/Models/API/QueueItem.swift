import Foundation

struct QueueItem: Codable, Identifiable {
    let filename: String
    let label: String
    let addedAt: String

    var id: String { filename }

    enum CodingKeys: String, CodingKey {
        case filename
        case label
        case addedAt = "added_at"
    }
}
