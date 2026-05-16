import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Query private var frames: [Frame]

    @State private var showUpload = false
    @State private var showQueue = false
    @State private var showSettings = false
    @State private var showPower = false
    @State private var showFramePicker = false
    @State private var showAddFrame = false
    @State private var selectedPalette: PaletteChoice = .rose

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack {
            appState.activeFrame == nil ? Color(pal.bg) : Color(pal.bg)

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    hero
                    FramePreviewCard()
                    ActionTiles(
                        onNewPhoto: { showUpload = true },
                        onQueue: { showQueue = true },
                        onSettings: { showSettings = true }
                    )
                    telemetry
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }

            if appState.isLoading {
                loadingOverlay
            }

            if let toast = appState.toastMessage {
                toastView(toast)
            }
        }
        .background(Color(pal.bg))
        .preferredColorScheme(selectedPalette.isDark ? .dark : .light)
        .sheet(isPresented: $showUpload) {
            UploadSheet(showNow: true)
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet(showAddPhoto: {
                showQueue = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showUpload = true }
            })
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(selectedPalette: $selectedPalette)
        }
        .sheet(isPresented: $showPower) {
            PowerSheet()
        }
        .sheet(isPresented: $showFramePicker) {
            FramePickerSheet(onAddFrame: { showAddFrame = true })
        }
        .fullScreenCover(isPresented: $showAddFrame) {
            AddFrameView()
        }
        .task {
            await appState.refresh()
            appState.startPolling()
        }
        .environment(\.palette, selectedPalette.palette)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                haptic(.soft)
                showFramePicker = true
            } label: {
                HStack(spacing: 4) {
                    Text("Plink")
                        .font(.custom("InstrumentSerif-Regular", size: 28))
                        .foregroundStyle(Color(pal.ink))
                    if let name = appState.activeFrame?.name {
                        Text("· \(name)")
                            .font(.custom("InstrumentSerif-Italic", size: 18))
                            .foregroundStyle(Color(pal.sub))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showPower = true
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(pal.ink))
                    .frame(width: 38, height: 38)
                    .background(Color(pal.chip), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(today)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color(pal.sub))
                .kerning(0.5)

            Text("Send a moment\nto your frame")
                .font(.custom("InstrumentSerif-Regular", size: 34))
                .foregroundStyle(Color(pal.ink))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private var telemetry: some View {
        HStack {
            telemetryItem(label: "MODE", value: appState.orientation == "portrait" ? "Portrait" : "Landscape")
            Divider().frame(height: 32)
            telemetryItem(label: "WI-FI", value: appState.status?.wifi ?? "--")
            Divider().frame(height: 32)
            telemetryItem(label: "UPTIME", value: appState.status?.uptime ?? "--")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 16)
    }

    private func telemetryItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color(pal.sub))
                .kerning(0.8)
            Text(value)
                .font(.custom("InstrumentSerif-Regular", size: 15))
                .foregroundStyle(Color(pal.ink))
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .blur(radius: 2)

            VStack(spacing: 14) {
                LoadingSpinner()
                    .foregroundStyle(Color(pal.accent))
                    .frame(width: 28, height: 28)
                Text(appState.loadingMessage)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(pal.ink))
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .glassCard()
        }
    }

    private func toastView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color(pal.accentInk))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(pal.accent), in: Capsule())
                .padding(.bottom, 48)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(duration: 0.3), value: appState.toastMessage)
    }
}

struct FramePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    @Query private var frames: [Frame]
    var onAddFrame: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(frames) { frame in
                    Button {
                        appState.activate(frame: frame)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(frame.name)
                                    .font(.system(.body, design: .monospaced, weight: .medium))
                                Text(frame.baseURL)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color(pal.sub))
                            }
                            Spacer()
                            if appState.activeFrame?.id == frame.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(pal.accent))
                            }
                        }
                    }
                    .foregroundStyle(Color(pal.ink))
                }
            }
            .navigationTitle("Frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onAddFrame() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
