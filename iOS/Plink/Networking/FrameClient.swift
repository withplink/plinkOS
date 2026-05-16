import Foundation

enum FrameAction: String {
    case reboot, shutdown, clearGhost = "clear_ghost", rotate
}

enum FrameClientError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid frame URL"
        case .serverError(let msg): return msg
        }
    }
}

actor FrameClient {
    let baseURL: URL
    private let statusSession: URLSession
    private let actionSession: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL

        let fast = URLSessionConfiguration.default
        fast.timeoutIntervalForRequest = 5
        fast.timeoutIntervalForResource = 8
        self.statusSession = URLSession(configuration: fast)

        let slow = URLSessionConfiguration.default
        slow.timeoutIntervalForRequest = 90
        slow.timeoutIntervalForResource = 120
        self.actionSession = URLSession(configuration: slow)
    }

    // MARK: - Status

    func status() async throws -> StatusResponse {
        let (data, _) = try await statusSession.data(from: url("/api/status"))
        return try decode(StatusResponse.self, from: data)
    }

    // MARK: - Queue

    func queue() async throws -> QueueResponse {
        let (data, _) = try await statusSession.data(from: url("/api/queue"))
        return try decode(QueueResponse.self, from: data)
    }

    func addToQueue(imageData: Data, label: String, showNow: Bool) async throws -> QueueResponse {
        var req = URLRequest(url: url("/api/queue/add"))
        req.httpMethod = "POST"
        let boundary = "PlinkBoundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = buildMultipart(boundary: boundary, imageData: imageData, label: label, showNow: showNow)
        let (data, _) = try await actionSession.data(for: req)
        let wrapper = try decode(QueueWrapper.self, from: data)
        guard let q = wrapper.queue else { throw FrameClientError.serverError(wrapper.error ?? "Unknown error") }
        return q
    }

    func removeFromQueue(index: Int) async throws -> QueueResponse {
        let wrapper = try await postJSONWrapped("/api/queue/remove", body: ["index": index])
        guard let q = wrapper.queue else { throw FrameClientError.serverError(wrapper.error ?? "Remove failed") }
        return q
    }

    func nextInQueue() async throws -> QueueResponse {
        let wrapper = try await postJSONWrapped("/api/queue/next", body: [:], useActionSession: true)
        guard let q = wrapper.queue else { throw FrameClientError.serverError(wrapper.error ?? "Next failed") }
        return q
    }

    func showQueueItem(index: Int) async throws -> QueueResponse {
        let wrapper = try await postJSONWrapped("/api/queue/show", body: ["index": index], useActionSession: true)
        guard let q = wrapper.queue else { throw FrameClientError.serverError(wrapper.error ?? "Show failed") }
        return q
    }

    func setInterval(minutes: Int) async throws {
        let _: SimpleOK = try await postJSON("/api/queue/interval", body: ["minutes": minutes])
    }

    // MARK: - Actions

    func action(_ action: FrameAction) async throws -> ActionResponse {
        var req = URLRequest(url: url("/api/action"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "action=\(action.rawValue)".data(using: .utf8)
        let (data, _) = try await actionSession.data(for: req)
        return try decode(ActionResponse.self, from: data)
    }

    func setOrientation(_ orientation: String) async throws {
        let _: SimpleOK = try await postJSON("/api/settings", body: ["orientation": orientation])
    }

    // MARK: - Image URL helper

    nonisolated func imageURL(for filename: String) -> URL {
        baseURL.appendingPathComponent("/uploads/\(filename)")
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func postJSONWrapped(_ path: String, body: [String: Any], useActionSession: Bool = false) async throws -> QueueWrapper {
        let session = useActionSession ? actionSession : statusSession
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try decode(QueueWrapper.self, from: data)
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await statusSession.data(for: req)
        return try decode(T.self, from: data)
    }

    private func buildMultipart(boundary: String, imageData: Data, label: String, showNow: Bool) -> Data {
        var body = Data()
        func field(_ name: String, value: String) {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!
        }
        body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!
        body += imageData
        body += "\r\n".data(using: .utf8)!
        field("label", value: label)
        field("show_now", value: showNow ? "1" : "0")
        body += "--\(boundary)--\r\n".data(using: .utf8)!
        return body
    }
}

private struct QueueWrapper: Codable {
    let ok: Bool?
    let queue: QueueResponse?
    let error: String?
}

private struct SimpleOK: Codable {
    let ok: Bool?
}
