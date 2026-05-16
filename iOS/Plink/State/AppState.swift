import Foundation
import SwiftUI

@Observable
final class AppState {
    var activeFrame: Frame?
    var status: StatusResponse?
    var queue: QueueResponse?
    var isOnline: Bool = false
    var isLoading: Bool = false
    var loadingMessage: String = ""
    var toastMessage: String? = nil
    var orientation: String = "landscape"

    private var pollingTask: Task<Void, Never>?
    private var client: FrameClient?

    func activate(frame: Frame) {
        activeFrame = frame
        guard let url = URL(string: frame.baseURL) else { return }
        client = FrameClient(baseURL: url)
        startPolling()
    }

    func deactivate() {
        pollingTask?.cancel()
        pollingTask = nil
        client = nil
        activeFrame = nil
        status = nil
        queue = nil
        isOnline = false
    }

    // MARK: - Polling

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: UInt64 = (self?.isOnline ?? false) ? 30_000_000_000 : 8_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func refresh() async {
        guard let client else { return }
        do {
            async let s = client.status()
            async let q = client.queue()
            let (statusResult, queueResult) = try await (s, q)
            await MainActor.run {
                self.status = statusResult
                self.queue = queueResult
                self.orientation = statusResult.orientation ?? "landscape"
                self.isOnline = true
                if let frame = self.activeFrame {
                    frame.lastSeen = Date()
                }
            }
        } catch {
            await MainActor.run {
                self.isOnline = false
            }
        }
    }

    // MARK: - Upload

    func upload(imageData: Data, label: String, showNow: Bool) async {
        guard let client else { return }
        await setLoading(showNow ? "Sending to display…" : "Adding to queue…")
        do {
            let response = try await client.addToQueue(imageData: imageData, label: label, showNow: showNow)
            if let q = response.queue {
                await MainActor.run { self.queue = q }
            }
            await clearLoading()
            await showToast(showNow ? "Sent to display" : "Photo added to queue")
        } catch {
            await clearLoading()
            await showToast("Upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Queue ops

    func removeFromQueue(index: Int) async {
        guard let client else { return }
        do {
            let q = try await client.removeFromQueue(index: index)
            await MainActor.run { self.queue = q }
        } catch {}
    }

    func nextInQueue() async {
        guard let client else { return }
        await setLoading("Next photo…")
        do {
            let q = try await client.nextInQueue()
            await MainActor.run { self.queue = q }
            await clearLoading()
        } catch {
            await clearLoading()
        }
    }

    func showQueueItem(index: Int) async {
        guard let client else { return }
        await setLoading("Switching…")
        do {
            let q = try await client.showQueueItem(index: index)
            await MainActor.run { self.queue = q }
            await clearLoading()
        } catch {
            await clearLoading()
        }
    }

    func setInterval(minutes: Int) async {
        guard let client else { return }
        try? await client.setInterval(minutes: minutes)
        await refresh()
    }

    // MARK: - Device actions

    func performAction(_ action: FrameAction, loadingMsg: String) async {
        guard let client else { return }
        await setLoading(loadingMsg)
        do {
            let result = try await client.action(action)
            if let imgURL = result.imageURL {
                await MainActor.run { self.status = StatusResponse(wifi: self.status?.wifi, uptime: self.status?.uptime, imageURL: imgURL, orientation: self.status?.orientation, lanIP: self.status?.lanIP) }
            }
            await clearLoading()
            if action == .reboot {
                await waitForReboot(client: client)
            }
        } catch {
            await clearLoading()
        }
    }

    private func waitForReboot(client: FrameClient) async {
        await setLoading("Reconnecting when Pi is back…")
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        for _ in 0..<60 {
            if let _ = try? await client.status() {
                await clearLoading()
                await refresh()
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        await clearLoading()
    }

    func setOrientation(_ orientation: String) async {
        guard let client else { return }
        try? await client.setOrientation(orientation)
        await MainActor.run { self.orientation = orientation }
    }

    func imageURL(for filename: String) -> URL? {
        client?.imageURL(for: filename)
    }

    // MARK: - UI helpers

    @MainActor func setLoading(_ message: String) {
        isLoading = true
        loadingMessage = message
    }

    @MainActor func clearLoading() {
        isLoading = false
        loadingMessage = ""
    }

    @MainActor func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }
}
