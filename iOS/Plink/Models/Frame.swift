import Foundation
import SwiftData

@Model
final class Frame {
    var id: UUID
    var name: String
    var baseURL: String
    var tailscaleURL: String?
    var lastSeen: Date?

    init(name: String, baseURL: String, tailscaleURL: String? = nil) {
        self.id = UUID()
        self.name = name
        self.baseURL = baseURL
        self.tailscaleURL = tailscaleURL
    }
}
