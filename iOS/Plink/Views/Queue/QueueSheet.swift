import SwiftUI

private let intervalOptions: [(label: String, minutes: Int)] = [
    ("Off", 0), ("30m", 30), ("1h", 60), ("2h", 120), ("6h", 360), ("12h", 720), ("24h", 1440)
]

struct QueueSheet: View {
    var showAddPhoto: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    intervalPicker
                    queueList
                    bottomActions
                }
                .padding(20)
            }
            .background(Color(pal.bg))
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(pal.sub))
                }
            }
        }
    }

    // MARK: - Interval picker

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTO-ROTATE")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Color(pal.sub))
                .kerning(0.8)

            HStack(spacing: 6) {
                ForEach(intervalOptions, id: \.minutes) { option in
                    let selected = appState.queue?.interval == option.minutes
                    Button {
                        haptic(.soft)
                        Task { await appState.setInterval(minutes: option.minutes) }
                    } label: {
                        Text(option.label)
                            .font(.system(.caption, design: .monospaced, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color(pal.accentInk) : Color(pal.ink))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? Color(pal.accent) : Color(pal.chip),
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Queue list

    private var queueList: some View {
        VStack(spacing: 8) {
            if let queue = appState.queue, !queue.items.isEmpty {
                ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                    queueRow(item: item, index: index, current: queue.current)
                }
            } else {
                Text("Queue is empty")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(pal.sub))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
    }

    private func queueRow(item: QueueItem, index: Int, current: Int) -> some View {
        let isCurrent = index == current
        return HStack(spacing: 12) {
            if let url = appState.imageURL(for: item.filename) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .saturation(isCurrent ? 1 : 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(pal.chip))
                            .frame(width: 56, height: 42)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color(pal.ink))
                    .lineLimit(1)
                Text(isCurrent ? "Now showing" : "#\(index + 1)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(isCurrent ? Color(pal.accent) : Color(pal.sub))
            }

            Spacer()

            Button {
                haptic(.error)
                Task { await appState.removeFromQueue(index: index) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(pal.sub))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isCurrent ? Color(pal.accent).opacity(0.08) : Color(pal.surf),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color(pal.accent).opacity(0.3) : Color(pal.line), lineWidth: 1)
        )
        .onTapGesture {
            guard !isCurrent else { return }
            haptic(.soft)
            Task { await appState.showQueueItem(index: index) }
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button {
                showAddPhoto()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add photo")
                        .font(.system(.subheadline, weight: .medium))
                }
                .foregroundStyle(Color(pal.ink))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(Color(pal.line))
                )
            }
            .buttonStyle(ScaleButtonStyle())

            let canNext = (appState.queue?.items.count ?? 0) >= 2
            Button {
                haptic(.soft)
                Task { await appState.nextInQueue() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward")
                        .font(.system(size: 13, weight: .medium))
                    Text("Next")
                        .font(.system(.subheadline, weight: .medium))
                }
                .foregroundStyle(canNext ? Color(pal.ink) : Color(pal.sub))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(pal.chip), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(pal.line), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canNext)
        }
    }
}
