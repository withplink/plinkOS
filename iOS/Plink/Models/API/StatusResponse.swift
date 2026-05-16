import Foundation

struct StatusResponse: Codable {
    let wifi: String?
    let uptime: String?
    let imageURL: String?
    let orientation: String?
    let lanIP: String?

    enum CodingKeys: String, CodingKey {
        case wifi
        case uptime
        case imageURL = "image_url"
        case orientation
        case lanIP = "lan_ip"
    }
}
