import SwiftUI

struct PowerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                rebootTile
                shutdownTile
                Spacer()
            }
            .padding(20)
            .background(Color(pal.bg))
            .navigationTitle("Power")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(pal.sub))
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    private var rebootTile: some View {
        Button {
            haptic(.soft)
            dismiss()
            Task { await appState.performAction(.reboot, loadingMsg: "Restarting…") }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(pal.accent))
                    .frame(width: 40, height: 40)
                    .background(Color(pal.chip), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restart")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color(pal.ink))
                    Text("Quick reboot, takes ~1 minute")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(pal.line))
            }
            .padding(16)
            .background(Color(pal.surf), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(pal.line), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var shutdownTile: some View {
        Button {
            haptic(.error)
            dismiss()
            Task { await appState.performAction(.shutdown, loadingMsg: "Shutting down…") }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "power")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(width: 40, height: 40)
                    .background(Color.red.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Power off")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color(pal.ink))
                    Text("Shutdown the Pi safely")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(pal.line))
            }
            .padding(16)
            .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
