import SwiftUI
import UIKit

struct CropView: View {
    let image: UIImage
    let aspectRatio: CGSize
    var onCancel: () -> Void
    var onSend: (Data) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @Environment(\.palette) private var pal

    private var cropSize: CGSize {
        let screenW = UIScreen.main.bounds.width
        let ratio = aspectRatio.height / aspectRatio.width
        let w = screenW - 48
        let h = w * ratio
        return CGSize(width: w, height: h)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Cropped image canvas
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cropSize.width * scale, height: cropSize.height * scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnificationGesture)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(cropOverlay)
            }

            VStack {
                // Header
                HStack {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(.white)
                        .padding()
                    Spacer()
                    Text("Frame it")
                        .font(.custom("InstrumentSerif-Regular", size: 20))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(aspectRatio.width))×\(Int(aspectRatio.height))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding()
                }
                .background(.ultraThinMaterial)

                Spacer()

                // Footer buttons
                HStack(spacing: 12) {
                    Button {
                        if let data = image.jpegData(compressionQuality: 0.92) {
                            onSend(data)
                        }
                    } label: {
                        Text("Send as is")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onSend(cropAndExport())
                    } label: {
                        Text("Crop & send")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var cropOverlay: some View {
        ZStack {
            // Dim outside crop region
            Color.black.opacity(0.4)
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: cropSize.width, height: cropSize.height)
                                .blendMode(.destinationOut)
                        )
                )

            // Rule-of-thirds grid
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.4), lineWidth: 1)
                .frame(width: cropSize.width, height: cropSize.height)
                .overlay(gridLines)
        }
        .allowsHitTesting(false)
    }

    private var gridLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Vertical thirds
                p.move(to: CGPoint(x: w / 3, y: 0))
                p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: 2 * w / 3, y: 0))
                p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // Horizontal thirds
                p.move(to: CGPoint(x: 0, y: h / 3))
                p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: 2 * h / 3))
                p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
        .frame(width: cropSize.width, height: cropSize.height)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
                clampOffset()
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
                clampOffset()
            }
    }

    private func clampOffset() {
        let maxX = (cropSize.width * scale - cropSize.width) / 2
        let maxY = (cropSize.height * scale - cropSize.height) / 2
        let newX = min(max(offset.width, -maxX), maxX)
        let newY = min(max(offset.height, -maxY), maxY)
        withAnimation(.spring(duration: 0.2)) {
            offset = CGSize(width: newX, height: newY)
            lastOffset = offset
        }
    }

    private func cropAndExport() -> Data {
        let targetSize = CGSize(width: aspectRatio.width, height: aspectRatio.height)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let result = renderer.jpegData(withCompressionQuality: 0.92) { ctx in
            let imgAspect = image.size.width / image.size.height
            let cropAspect = targetSize.width / targetSize.height
            var drawSize: CGSize
            if imgAspect > cropAspect {
                drawSize = CGSize(width: targetSize.height * imgAspect, height: targetSize.height)
            } else {
                drawSize = CGSize(width: targetSize.width, height: targetSize.width / imgAspect)
            }
            // Apply user offset scaled to output resolution
            let scaleToOutput = targetSize.width / cropSize.width
            let scaledOffsetX = offset.width * scaleToOutput / scale
            let scaledOffsetY = offset.height * scaleToOutput / scale
            let origin = CGPoint(
                x: (targetSize.width - drawSize.width * scale) / 2 + scaledOffsetX,
                y: (targetSize.height - drawSize.height * scale) / 2 + scaledOffsetY
            )
            image.draw(in: CGRect(origin: origin, size: CGSize(width: drawSize.width * scale, height: drawSize.height * scale)))
        }
        return result
    }
}
