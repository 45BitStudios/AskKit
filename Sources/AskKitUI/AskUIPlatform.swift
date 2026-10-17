import AskKit
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    /// An image from the system image type on this platform.
    init(askImage image: AskPlatformImage) {
#if canImport(UIKit)
        self.init(uiImage: image)
#elseif canImport(AppKit)
        self.init(nsImage: image)
#endif
    }
}

@MainActor
extension ImageRenderer {
    /// The rendered image in the system image type on this platform.
    var askImage: AskPlatformImage? {
#if canImport(UIKit)
        uiImage
#elseif canImport(AppKit)
        nsImage
#endif
    }
}

/// Hue and RGB parts of a SwiftUI color, read the way UIKit and AppKit read them.
enum AskColorParts {
    static func hsb(_ color: Color) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)? {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
#if canImport(UIKit)
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return nil }
#elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
#endif
        return (hue, saturation, brightness)
    }

    static func rgb(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
#if canImport(UIKit)
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
#elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        srgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#endif
        return (red, green, blue)
    }
}

/// Copy for the card and bubble menus. Apple TV and Apple Watch have no pasteboard.
enum AskPasteboard {
    static var isAvailable: Bool {
#if os(iOS) || os(visionOS) || os(macOS)
        true
#else
        false
#endif
    }

    static func copy(text: String? = nil, png: Data? = nil) {
#if os(iOS) || os(visionOS)
        var item: [String: Any] = [:]
        if let text { item[UTType.utf8PlainText.identifier] = text }
        if let png { item[UTType.png.identifier] = png }
        guard !item.isEmpty else { return }
        UIPasteboard.general.items = [item]
#elseif os(macOS)
        guard text != nil || png != nil else { return }
        let board = NSPasteboard.general
        board.clearContents()
        if let text { board.setString(text, forType: .string) }
        if let png { board.setData(png, forType: .png) }
#endif
    }
}

extension ToolbarItemPlacement {
    /// The leading bar slot, or the navigation area on the Mac.
    static var askLeading: ToolbarItemPlacement {
#if os(macOS)
        .navigation
#elseif os(tvOS)
        .automatic
#else
        .topBarLeading
#endif
    }

    /// The trailing bar slot, or the primary action area on the Mac.
    static var askTrailing: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#elseif os(tvOS)
        .automatic
#else
        .topBarTrailing
#endif
    }
}

extension View {
    /// An inline navigation title where the platform has one.
    @ViewBuilder
    func askInlineTitle() -> some View {
#if os(iOS) || os(visionOS) || os(watchOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    /// A large navigation title where the platform has one.
    @ViewBuilder
    func askLargeTitle() -> some View {
#if os(iOS) || os(visionOS) || os(watchOS)
        navigationBarTitleDisplayMode(.large)
#else
        self
#endif
    }

    /// The zoom push from a matched source. The Mac pushes without it.
    @ViewBuilder
    func askZoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
#if os(macOS)
        self
#else
        navigationTransition(.zoom(sourceID: sourceID, in: namespace))
#endif
    }

    /// A clear navigation bar, where there is one.
    @ViewBuilder
    func askHiddenBarBackground() -> some View {
#if os(macOS)
        self
#else
        toolbarBackground(.hidden, for: .navigationBar)
#endif
    }

    /// Liquid Glass behind a view. visionOS draws its own glass material instead.
    @ViewBuilder
    func askGlass(tint: Color? = nil, in shape: some InsettableShape) -> some View {
#if os(visionOS)
        glassBackgroundEffect(in: shape)
#else
        glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
#endif
    }

    /// Selectable text where the platform has a selection. Apple TV and Apple Watch do not.
    @ViewBuilder
    func askSelectable() -> some View {
#if os(tvOS) || os(watchOS)
        self
#else
        textSelection(.enabled)
#endif
    }

    /// A bordered text field where the platform draws one.
    @ViewBuilder
    func askRoundedField() -> some View {
#if os(tvOS) || os(watchOS)
        self
#else
        textFieldStyle(.roundedBorder)
#endif
    }

    /// A full-screen cover, or a sheet on the Mac.
    func askFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
#if os(macOS)
        sheet(isPresented: isPresented, content: content)
#else
        fullScreenCover(isPresented: isPresented, content: content)
#endif
    }

    /// A full-screen cover for an item, or a sheet on the Mac.
    func askFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
#if os(macOS)
        sheet(item: item, content: content)
#else
        fullScreenCover(item: item, content: content)
#endif
    }
}

#if os(iOS) || os(visionOS)
/// The system share sheet for a card, a photo, or a trace.
struct AskCardActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController,
           let window = Self.keyWindow() {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 1, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
#else
/// Share buttons for a card, a photo, or a trace. Apple TV has no share sheet, so the words are shown instead.
struct AskCardActivityView: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(item)
                }
            }
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: Any) -> some View {
        if let text = item as? String {
#if os(tvOS)
            Text(text)
#else
            ShareLink(item: text) {
                Label(text, systemImage: "text.quote")
                    .lineLimit(2)
            }
#endif
        } else if let picture = item as? AskPlatformImage {
            let image = Image(askImage: picture)
#if os(tvOS)
            image
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
#else
            ShareLink(item: image, preview: SharePreview("Picture", image: image)) {
                Label("Picture", systemImage: "photo")
            }
#endif
        } else if let url = item as? URL {
#if os(tvOS)
            Text(url.lastPathComponent)
#else
            ShareLink(item: url) {
                Label(url.lastPathComponent, systemImage: "doc")
            }
#endif
        }
    }
}
#endif
