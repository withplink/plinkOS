import SwiftUI

struct SettingsSheet: View {
    @Binding var selectedPalette: PaletteChoice
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    orientationSection
                    themeSection
                    maintenanceSection
                    deviceInfoSection
                }
                .padding(20)
            }
            .background(Color(pal.bg))
            .navigationTitle("Tune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(pal.sub))
                }
            }
        }
    }

    // MARK: - Orientation

    private var orientationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ORIENTATION")

            HStack(spacing: 10) {
                orientationButton(label: "Landscape", dims: "800×480", value: "landscape")
                orientationButton(label: "Portrait", dims: "480×800", value: "portrait")
            }
        }
    }

    private func orientationButton(label: String, dims: String, value: String) -> some View {
        let selected = appState.orientation == value
        return Button {
            haptic(.soft)
            Task { await appState.setOrientation(value) }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(.subheadline, weight: .medium))
                Text(dims)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(selected ? Color(pal.accentInk).opacity(0.7) : Color(pal.sub))
            }
            .foregroundStyle(selected ? Color(pal.accentInk) : Color(pal.ink))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? Color(pal.accent) : Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : Color(pal.line), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("THEME")

            HStack(spacing: 12) {
                ForEach(PaletteChoice.allCases, id: \.self) { choice in
                    Button {
                        haptic(.soft)
                        selectedPalette = choice
                    } label: {
                        Circle()
                            .fill(choice.swatch)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color(pal.ink), lineWidth: selectedPalette == choice ? 2.5 : 0)
                                    .padding(2)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                Spacer()
            }
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("MAINTENANCE")

            HStack(spacing: 10) {
                maintenanceTile(
                    icon: "rotate.left",
                    title: "Rotate 90°",
                    sub: "Redisplays image"
                ) {
                    Task { await appState.performAction(.rotate, loadingMsg: "Rotating…") }
                }

                maintenanceTile(
                    icon: "eraser",
                    title: "Clear ghosting",
                    sub: "3-cycle refresh"
                ) {
                    Task { await appState.performAction(.clearGhost, loadingMsg: "Clearing ghosting…") }
                }
            }
        }
    }

    private func maintenanceTile(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(pal.accent))
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Color(pal.ink))
                    Text(sub)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(pal.line), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Device info

    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DEVICE")

            HStack {
                infoItem(label: "WI-FI", value: appState.status?.wifi ?? "--")
                Divider().frame(height: 32)
                infoItem(label: "UPTIME", value: appState.status?.uptime ?? "--")
                Divider().frame(height: 32)
                infoItem(label: "HOST", value: appState.activeFrame?.baseURL.replacingOccurrences(of: "http://", with: "") ?? "--")
            }
            .padding(16)
            .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoItem(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color(pal.sub))
                .kerning(0.6)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(pal.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(Color(pal.sub))
            .kerning(0.8)
    }
}
