import Foundation

struct QueueResponse: Codable {
    let items: [QueueItem]
    let current: Int
    let interval: Int
}

struct AddQueueResponse: Codable {
    let ok: Bool
    let imageURL: String?
    let queue: QueueResponse?

    enum CodingKeys: String, CodingKey {
        case ok
        case imageURL = "image_url"
        case queue
    }
}

struct ActionResponse: Codable {
    let ok: Bool?
    let imageURL: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case imageURL = "image_url"
        case error
    }
}
