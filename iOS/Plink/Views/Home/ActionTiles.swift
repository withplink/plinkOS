import SwiftUI

struct ActionTiles: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    var onNewPhoto: () -> Void
    var onQueue: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Primary: New photo (full width)
            Button {
                haptic(.soft)
                onNewPhoto()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New photo")
                            .font(.system(.body, weight: .semibold))
                        Text("From device")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(pal.accentInk).opacity(0.75))
                    }
                    Spacer()
                }
                .foregroundStyle(Color(pal.accentInk))
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Color(pal.accent), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ScaleButtonStyle())

            // Secondary row: Queue + Settings
            HStack(spacing: 10) {
                Button {
                    onQueue()
                } label: {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "list.number")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if let count = appState.queue?.items.count, count > 0 {
                                Text("\(count)")
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(pal.accent).opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color(pal.accent))
                            }
                        }
                        Text("Queue")
                            .font(.system(.subheadline, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Color(pal.ink))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(pal.line), lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    onSettings()
                } label: {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Text(appState.orientation == "portrait" ? "P" : "L")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(pal.chip), in: Capsule())
                                .foregroundStyle(Color(pal.sub))
                        }
                        Text("Tune")
                            .font(.system(.subheadline, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Color(pal.ink))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(pal.line), lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
