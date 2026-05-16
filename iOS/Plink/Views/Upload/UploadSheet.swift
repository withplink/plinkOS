import SwiftUI
import PhotosUI

struct UploadSheet: View {
    var showNow: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var loadedImage: UIImage?
    @State private var showCrop = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(pal.accent))

                    Text("Choose a photo")
                        .font(.custom("InstrumentSerif-Regular", size: 26))
                        .foregroundStyle(Color(pal.ink))

                    Text(showNow ? "It will be sent to your frame immediately" : "It will be added to your queue")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color(pal.sub))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17, weight: .medium))
                        Text("Open Photos")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(Color(pal.accentInk))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(pal.accent), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                }
                .buttonStyle(ScaleButtonStyle())
                .onChange(of: selectedItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                loadedImage = image
                                showCrop = true
                            }
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(pal.bg))
            .navigationTitle(showNow ? "New Photo" : "Add to Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(pal.sub))
                }
            }
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let image = loadedImage {
                let ratio = appState.orientation == "portrait"
                    ? CGSize(width: 480, height: 800)
                    : CGSize(width: 800, height: 480)
                CropView(
                    image: image,
                    aspectRatio: ratio,
                    onCancel: {
                        showCrop = false
                        selectedItem = nil
                    },
                    onSend: { data in
                        showCrop = false
                        dismiss()
                        Task {
                            await appState.upload(imageData: data, label: "Photo", showNow: showNow)
                        }
                    }
                )
                .environment(\.palette, pal)
            }
        }
    }
}
