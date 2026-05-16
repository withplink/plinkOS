import SwiftUI
import SwiftData

@main
struct PiLinkApp: App {
    @State private var appState = AppState()
    @State private var selectedPalette: PaletteChoice = {
        let raw = UserDefaults.standard.string(forKey: "selectedPalette") ?? "rose"
        return PaletteChoice(rawValue: raw) ?? .rose
    }()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Frame.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.palette, selectedPalette.palette)
                .preferredColorScheme(selectedPalette.isDark ? .dark : .light)
        }
        .modelContainer(sharedModelContainer)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Query private var frames: [Frame]
    @State private var hasActivated = false

    var body: some View {
        Group {
            if appState.activeFrame != nil {
                HomeView()
            } else {
                AddFrameView()
            }
        }
        .onAppear {
            guard !hasActivated, let first = frames.first else { return }
            hasActivated = true
            appState.activate(frame: first)
        }
    }
}
