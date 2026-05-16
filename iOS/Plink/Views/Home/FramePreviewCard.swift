import SwiftUI

struct FramePreviewCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal

    private var isPortrait: Bool { appState.orientation == "portrait" }
    private let frameW: CGFloat = 200
    private var frameH: CGFloat { isPortrait ? 286 : 130 }

    var body: some View {
        VStack(spacing: 0) {
            // E-ink frame preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(pal.chip))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(pal.line), lineWidth: 1)
                    )
                    .frame(width: frameW, height: frameH)

                if let status = appState.status,
                   let imgPath = status.imageURL,
                   let url = appState.imageURL(for: imgPath.replacingOccurrences(of: "/uploads/", with: "")) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: frameW, height: frameH)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        default:
                            noImagePlaceholder
                        }
                    }
                } else {
                    noImagePlaceholder
                }
            }
            .padding(.bottom, 14)

            // Device info row
            HStack(spacing: 8) {
                // Device name
                Text("plnk·\(appState.activeFrame?.name.suffix(2) ?? "01")")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color(pal.sub))

                Spacer()

                // Status dot + text
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isOnline ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(appState.isOnline
                         ? "Online · \(appState.status?.uptime ?? "--")"
                         : "Offline · reconnecting")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }
            }
            .frame(width: frameW)

            // Tailscale / pi.local hint
            tailscaleHint
                .frame(width: frameW, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var tailscaleHint: some View {
        if !appState.isOnline, let frame = appState.activeFrame,
           !frame.baseURL.contains("tail") {
            Button {
                if let url = URL(string: frame.baseURL) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("pi.local ↗")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(pal.accent))
            }
            .buttonStyle(.plain)
        } else if appState.isOnline, let frame = appState.activeFrame,
                  !frame.baseURL.contains("tail"),
                  let tailURL = frame.tailscaleURL {
            Button {
                if let url = URL(string: tailURL) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("switch to tailscale ↗")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(pal.sub))
            }
            .buttonStyle(.plain)
        }
    }

    private var noImagePlaceholder: some View {
        Text("NO IMAGE")
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(Color(pal.sub))
            .kerning(1)
    }
}
