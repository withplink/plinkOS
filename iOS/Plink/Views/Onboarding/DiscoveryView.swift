import SwiftUI

struct DiscoveryView: View {
    @Bindable var discovery: FrameDiscovery
    var onSelect: (String, String) -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(spacing: 0) {
            if discovery.isSearching && discovery.frames.isEmpty {
                HStack(spacing: 12) {
                    LoadingSpinner()
                        .foregroundStyle(Color(pal.accent))
                        .frame(width: 18, height: 18)
                    Text("Scanning for frames…")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                }
                .padding(.vertical, 24)
            }

            if !discovery.frames.isEmpty {
                VStack(spacing: 8) {
                    Text("FOUND NEARBY")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(Color(pal.sub))
                        .kerning(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    ForEach(discovery.frames) { frame in
                        Button {
                            haptic(.soft)
                            onSelect(frame.baseURL, frame.name)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "display.and.arrow.down")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color(pal.accent))
                                    .frame(width: 40, height: 40)
                                    .background(Color(pal.chip), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(frame.name)
                                        .font(.system(.body, weight: .semibold))
                                        .foregroundStyle(Color(pal.ink))
                                    Text(frame.baseURL)
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
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}
