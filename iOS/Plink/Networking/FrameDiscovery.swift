import Foundation
import Network

struct DiscoveredFrame: Identifiable {
    let id = UUID()
    let name: String
    let baseURL: String
}

@Observable
final class FrameDiscovery {
    var frames: [DiscoveredFrame] = []
    var isSearching = false

    private var browser: NWBrowser?
    private var resolutionTasks: [UUID: Task<Void, Never>] = [:]

    func start() {
        isSearching = true
        frames = []

        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_plink._tcp", domain: "local"), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.isSearching = false }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                self.handleResult(result)
            }
        }

        browser?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolutionTasks.values.forEach { $0.cancel() }
        resolutionTasks.removeAll()
        isSearching = false
    }

    private func handleResult(_ result: NWBrowser.Result) {
        guard case .service(let name, _, let domain, _) = result.endpoint else { return }

        let taskID = UUID()
        let task = Task { [weak self] in
            guard let url = await self?.resolve(result.endpoint, name: name, domain: domain) else { return }
            await MainActor.run {
                guard let self else { return }
                if !self.frames.contains(where: { $0.baseURL == url }) {
                    self.frames.append(DiscoveredFrame(name: name, baseURL: url))
                }
                self.resolutionTasks.removeValue(forKey: taskID)
            }
        }
        resolutionTasks[taskID] = task
    }

    private func resolve(_ endpoint: NWEndpoint, name: String, domain: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let conn = NWConnection(to: endpoint, using: .tcp)
            var resolved = false

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let remote = conn.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = remote,
                       !resolved {
                        resolved = true
                        conn.cancel()
                        let ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                        let portStr = port == 80 ? "" : ":\(port)"
                        continuation.resume(returning: "http://\(ip)\(portStr)")
                    }
                case .failed, .cancelled:
                    if !resolved {
                        resolved = true
                        conn.cancel()
                        // Fallback: try hostname.local
                        let host = name.lowercased().replacingOccurrences(of: " ", with: "-")
                        continuation.resume(returning: "http://\(host).local")
                    }
                default:
                    break
                }
            }

            conn.start(queue: .global(qos: .userInitiated))

            // Timeout after 4s
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if !resolved {
                    resolved = true
                    conn.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
