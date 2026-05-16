import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Share extension entry point — presents a compact SwiftUI sheet
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let container = try? ModelContainer(for: Frame.self, configurations: ModelConfiguration(groupContainer: .identifier("group.com.pcode.plink")))
        let hostingVC = UIHostingController(rootView: ShareRootView(context: extensionContext!, modelContainer: container))
        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.view.frame = view.bounds
        hostingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingVC.didMove(toParent: self)
    }
}

struct ShareRootView: View {
    let context: NSExtensionContext
    var modelContainer: ModelContainer?

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var selectedFrame: Frame?
    @State private var showCrop = false
    @State private var isSending = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading image…")
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()

                    if let container = modelContainer {
                        FramePickerInline(modelContainer: container, selected: $selectedFrame)
                    }

                    Button {
                        showCrop = true
                    } label: {
                        Label("Crop & Send", systemImage: "photo.badge.checkmark")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .disabled(selectedFrame == nil || isSending)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Send to Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { context.completeRequest(returningItems: [], completionHandler: nil) }
                }
            }
        }
        .onAppear { loadImage() }
        .fullScreenCover(isPresented: $showCrop) {
            if let img = image, let frame = selectedFrame, let url = URL(string: frame.baseURL) {
                CropView(
                    image: img,
                    aspectRatio: CGSize(width: 800, height: 480),
                    onCancel: { showCrop = false },
                    onSend: { data in
                        showCrop = false
                        isSending = true
                        Task {
                            let client = FrameClient(baseURL: url)
                            try? await client.addToQueue(imageData: data, label: "Shared photo", showNow: true)
                            context.completeRequest(returningItems: [], completionHandler: nil)
                        }
                    }
                )
            }
        }
        .if(modelContainer != nil) { v in
            v.modelContainer(modelContainer!)
        }
    }

    private func loadImage() {
        guard let provider = context.inputItems
            .compactMap({ $0 as? NSExtensionItem })
            .flatMap({ $0.attachments ?? [] })
            .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            isLoading = false
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
            DispatchQueue.main.async {
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    self.image = UIImage(data: data)
                } else if let img = item as? UIImage {
                    self.image = img
                }
                self.isLoading = false
            }
        }
    }
}

struct FramePickerInline: View {
    var modelContainer: ModelContainer
    @Binding var selected: Frame?
    @Query private var frames: [Frame]

    init(modelContainer: ModelContainer, selected: Binding<Frame?>) {
        self.modelContainer = modelContainer
        self._selected = selected
    }

    var body: some View {
        if frames.count > 1 {
            Picker("Frame", selection: $selected) {
                Text("Select frame").tag(Optional<Frame>.none)
                ForEach(frames) { frame in
                    Text(frame.name).tag(Optional(frame))
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
        } else if let first = frames.first {
            Color.clear.onAppear { selected = first }
        }
    }
}

extension View {
    @ViewBuilder func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
