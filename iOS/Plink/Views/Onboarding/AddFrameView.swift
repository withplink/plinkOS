import SwiftUI
import SwiftData

struct AddFrameView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var pal

    @State private var discovery = FrameDiscovery()
    @State private var showManual = false
    @State private var isConnecting = false
    @State private var connectError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(pal.bg).ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    DiscoveryView(discovery: discovery, onSelect: connect)
                    Divider().padding(.horizontal, 24)
                    manualEntrySection
                }
            }
            .navigationTitle("Add Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !appState.activeFrame.isNone {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color(pal.sub))
                    }
                }
            }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.fill.badge.wifi")
                .font(.system(size: 40))
                .foregroundStyle(Color(pal.accent))
                .padding(.top, 32)

            Text("Find your frame")
                .font(.custom("InstrumentSerif-Regular", size: 28))
                .foregroundStyle(Color(pal.ink))

            Text("Make sure your Pi and iPhone are on the same WiFi network.")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Color(pal.sub))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
    }

    private var manualEntrySection: some View {
        VStack(spacing: 12) {
            Text("OR")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color(pal.sub))
                .padding(.top, 16)

            NavigationLink("Enter IP or hostname manually") {
                ManualEntryView(onConnect: connect)
            }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(Color(pal.accent))

            hotspotHint
        }
        .padding(.bottom, 40)
    }

    private var hotspotHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO WIFI? USE PI HOTSPOT")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color(pal.sub))
                .kerning(0.6)

            VStack(alignment: .leading, spacing: 4) {
                hotspotStep("1.", "Hold Button A on your frame for 1.5s")
                hotspotStep("2.", "Connect iPhone to "plink-setup" WiFi")
                hotspotStep("3.", "Your frame will appear above automatically")
            }
        }
        .padding(16)
        .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func hotspotStep(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Color(pal.accent))
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(pal.ink))
        }
    }

    private func connect(baseURL: String, name: String) {
        guard let url = URL(string: baseURL) else { return }
        isConnecting = true
        Task {
            let client = FrameClient(baseURL: url)
            do {
                let status = try await client.status()
                let frame = Frame(name: name, baseURL: baseURL)
                await MainActor.run {
                    modelContext.insert(frame)
                    appState.activate(frame: frame)
                    isConnecting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectError = "Couldn't reach frame: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension Optional where Wrapped == Frame {
    var isNone: Bool { self == nil }
}
