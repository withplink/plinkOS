import SwiftUI

struct ManualEntryView: View {
    var onConnect: (String, String) -> Void
    @Environment(\.palette) private var pal
    @State private var host = ""
    @State private var name = "My Frame"
    @State private var isConnecting = false
    @State private var error: String?

    private var normalizedURL: String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    label("FRAME NAME")
                    TextField("My Frame", text: $name)
                        .textFieldStyle(PlinkTextFieldStyle(pal: pal))
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("HOSTNAME OR IP")
                    TextField("pi.local or 192.168.1.42", text: $host)
                        .textFieldStyle(PlinkTextFieldStyle(pal: pal))
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    Text("Tailscale: enter the full https://… URL")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }

                if let error {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.red.opacity(0.8))
                }

                Button {
                    guard let url = normalizedURL else { return }
                    haptic(.soft)
                    isConnecting = true
                    self.error = nil
                    onConnect(url, name.isEmpty ? "My Frame" : name)
                } label: {
                    HStack {
                        if isConnecting {
                            LoadingSpinner()
                                .foregroundStyle(Color(pal.accentInk))
                                .frame(width: 18, height: 18)
                        }
                        Text(isConnecting ? "Connecting…" : "Connect")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(Color(pal.accentInk))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(normalizedURL != nil ? Color(pal.accent) : Color(pal.chip),
                                in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(normalizedURL == nil || isConnecting)
            }
            .padding(24)
        }
        .background(Color(pal.bg))
        .navigationTitle("Manual Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(Color(pal.sub))
            .kerning(0.6)
    }
}

struct PlinkTextFieldStyle: TextFieldStyle {
    let pal: Palette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color(pal.ink))
            .padding(14)
            .background(Color(pal.surf), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(pal.line), lineWidth: 1)
            )
    }
}
