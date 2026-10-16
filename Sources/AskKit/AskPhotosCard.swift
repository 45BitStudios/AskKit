import Photos
import SwiftUI
import UIKit

/// Opens the library gallery from a photo card. The chat screen owns the zoom namespace.
@MainActor
@Observable
final class AskLibraryGallery {
    var photos: [AskPhotosLine.Photo] = []
    var startID: String?
    var sourcePrefix = ""
    /// Cell the dismiss animation returns to. Photos past the fourth use the last cell.
    var zoomID = ""
    /// Separate from `startID` so closing does not clear the page the dismiss animation is using.
    var presented = false

    func open(_ photos: [AskPhotosLine.Photo], at id: String, sourcePrefix: String) {
        self.photos = photos
        self.sourcePrefix = sourcePrefix
        zoomID = AskPhotosLine.zoomSource(prefix: sourcePrefix, photoID: id, ids: photos.map(\.id))
        startID = id
        presented = true
    }
}

extension EnvironmentValues {
    @Entry var libraryGallery: AskLibraryGallery?
    /// The chat NavigationStack's zoom namespace. Nil when the card presents itself.
    @Entry var libraryZoomNamespace: Namespace.ID?
}

/// Four library photos in a square. The last cell counts the ones that did not fit.
struct AskPhotosCard: View {
    var title: String
    var photos: [AskPhotosLine.Photo]
    var shareText = ""

    @Environment(\.libraryGallery) private var gallery
    @Environment(\.libraryZoomNamespace) private var chatZoom
    @Namespace private var localZoom
    @State private var token = UUID()
    @State private var localStart: String?
    @State private var localPresented = false
    @State private var localZoomID = ""
    @State private var cardWidth: CGFloat = 0

    private var zoom: Namespace.ID {
        chatZoom ?? localZoom
    }

    var body: some View {
        column
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, width in
                            cardWidth = width
                        }
                }
            }
            .modifier(localDestination)
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 12) {
            AskPhotosCardHeader(title: title)
                .modifier(AskCardActions(text: shareText, width: cardWidth, view: AnyView(preview)))
            AskPhotosGrid(
                photos: photos,
                sourcePrefix: token.uuidString,
                namespace: zoom,
                onOpen: open
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { AskPhotosCardFill() }
    }

    /// The chat stack presents the gallery. A second destination on the card hides the zoom source.
    private var localDestination: AskPhotosLocalDestination {
        AskPhotosLocalDestination(
            enabled: chatZoom == nil,
            photos: photos,
            sourcePrefix: token.uuidString,
            startID: $localStart,
            presented: $localPresented,
            zoomID: $localZoomID,
            zoom: localZoom
        )
    }

    /// Long-press picture of the card. It stays out of the chat, so its cells do not take the zoom source.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            AskPhotosCardHeader(title: title)
            AskPhotosGrid(
                photos: photos,
                sourcePrefix: "preview",
                namespace: localZoom,
                marksZoom: false,
                onOpen: { _ in }
            )
        }
        .padding(16)
        .frame(width: cardWidth > 1 ? cardWidth : 300, alignment: .leading)
        .background { AskPhotosCardFill() }
    }

    private func open(_ id: String) {
        AskCue.tap()
        if chatZoom != nil, let gallery {
            gallery.open(photos, at: id, sourcePrefix: token.uuidString)
        } else {
            localZoomID = AskPhotosLine.zoomSource(prefix: token.uuidString, photoID: id, ids: photos.map(\.id))
            localStart = id
            localPresented = true
        }
    }
}

/// The card fill stays rounded without clipping the cells. A clipped ancestor breaks the zoom.
private struct AskPhotosCardFill: View {
    @Environment(\.askBubbleFill) private var fill

    var body: some View {
        AskCardStyle.shape.fill(fill)
    }
}

private struct AskPhotosCardHeader: View {
    var title: String

    var body: some View {
        AskCardMark(
            title: title.isEmpty ? "Photos" : title,
            symbol: "photo.on.rectangle",
            tint: AskCardSymbol.tint(for: "Photos")
        )
    }
}

private struct AskPhotosGrid: View {
    var photos: [AskPhotosLine.Photo]
    var sourcePrefix: String
    var namespace: Namespace.ID
    var marksZoom = true
    var onOpen: (String) -> Void

    private var cells: [AskPhotosLine.Photo] {
        Array(photos.prefix(AskPhotosLine.gridCount))
    }

    var body: some View {
        if cells.count <= 1, let photo = cells.first {
            AskPhotoCell(
                photo: photo,
                sourceID: AskPhotosLine.zoomSource(prefix: sourcePrefix, photoID: photo.id, ids: photos.map(\.id)),
                position: 1,
                total: photos.count,
                overflow: 0,
                namespace: namespace,
                marksZoom: marksZoom,
                onOpen: { onOpen(photo.id) }
            )
        } else {
            VStack(spacing: 3) {
                AskPhotosGridRow(
                    photos: photos,
                    cells: cells,
                    start: 0,
                    sourcePrefix: sourcePrefix,
                    namespace: namespace,
                    marksZoom: marksZoom,
                    onOpen: onOpen
                )
                if cells.count > 2 {
                    AskPhotosGridRow(
                        photos: photos,
                        cells: cells,
                        start: 2,
                        sourcePrefix: sourcePrefix,
                        namespace: namespace,
                        marksZoom: marksZoom,
                        onOpen: onOpen
                    )
                }
            }
        }
    }
}

private struct AskPhotosGridRow: View {
    var photos: [AskPhotosLine.Photo]
    var cells: [AskPhotosLine.Photo]
    var start: Int
    var sourcePrefix: String
    var namespace: Namespace.ID
    var marksZoom: Bool
    var onOpen: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            slot(start)
            slot(start + 1)
        }
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if cells.indices.contains(index) {
            let photo = cells[index]
            let leftover = index == cells.count - 1 ? AskPhotosLine.overflow(count: photos.count) : 0
            AskPhotoCell(
                photo: photo,
                sourceID: AskPhotosLine.zoomSource(prefix: sourcePrefix, photoID: photo.id, ids: photos.map(\.id)),
                position: index + 1,
                total: photos.count,
                overflow: leftover,
                namespace: namespace,
                marksZoom: marksZoom,
                onOpen: { onOpen(photo.id) }
            )
        } else {
            AskPhotoSquare {
                Color.clear
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AskPhotoCell: View {
    var photo: AskPhotosLine.Photo
    var sourceID: String
    var position: Int
    var total: Int
    var overflow: Int
    var namespace: Namespace.ID
    var marksZoom: Bool
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            // The square is the zoom source. A source inside the GeometryReader reports a frame the transition cannot match, so the zoom grows from the middle of the screen.
            AskPhotoSquare {
                GeometryReader { proxy in
                    face
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .modifier(AskPhotoZoomMark(enabled: marksZoom, sourceID: sourceID, namespace: namespace))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Shows the photos")
    }

    private var face: some View {
        ZStack {
            AskPhotoThumb(localIdentifier: photo.id)
            if overflow > 0 {
                Color.black.opacity(0.55)
                Text(verbatim: "+\(overflow)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
        }
    }

    private var label: String {
        if overflow > 0 {
            return "\(photo.caption), plus \(overflow) more"
        }
        if total > 1 {
            return "\(photo.caption), \(position) of \(total)"
        }
        return photo.caption
    }
}

/// A 1:1 slot sized from the proposed width. The photo's own height is ignored, so a portrait screenshot stays cropped.
private struct AskPhotoSquare: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = Self.side(for: proposal)
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let proposed = ProposedViewSize(width: bounds.width, height: bounds.height)
        let origin = CGPoint(x: bounds.midX, y: bounds.midY)
        for subview in subviews {
            subview.place(at: origin, anchor: .center, proposal: proposed)
        }
    }

    private static func side(for proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 { return width }
        if let height = proposal.height, height.isFinite, height > 0 { return height }
        return 0
    }
}

/// Marks the photo the gallery zooms from. A long-press preview leaves this off so it cannot steal the source.
private struct AskPhotoZoomMark: ViewModifier {
    var enabled: Bool
    var sourceID: String
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if enabled {
            content.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct AskPhotoThumb: View {
    var localIdentifier: String

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: localIdentifier) {
            image = await AskPhotoLibraryImage.load(
                localIdentifier,
                points: 220,
                scale: displayScale,
                quality: .thumbnail
            )
        }
    }
}

/// Used when the card is outside the chat, such as the Cards sheet.
private struct AskPhotosLocalDestination: ViewModifier {
    var enabled: Bool
    var photos: [AskPhotosLine.Photo]
    var sourcePrefix: String
    @Binding var startID: String?
    @Binding var presented: Bool
    @Binding var zoomID: String
    var zoom: Namespace.ID

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: isPresented) {
                AskPhotosGallery(
                    photos: photos,
                    startID: startID ?? "",
                    sourcePrefix: sourcePrefix,
                    zoomID: $zoomID
                )
                .navigationTransition(.zoom(sourceID: zoomID, in: zoom))
            }
        } else {
            content
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { enabled && presented },
            set: { if !$0 { presented = false } }
        )
    }
}

/// Every matched photo, starting from the one that was tapped. Swipe moves between them.
struct AskPhotosGallery: View {
    var photos: [AskPhotosLine.Photo]
    var startID: String
    var sourcePrefix: String
    @Binding var zoomID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// Swipe choice. It applies only while `choiceStart` is still this open's start id.
    @State private var choiceStart: String?
    @State private var choiceID: String?
    @State private var drag: CGFloat = 0
    @State private var scales: [String: CGFloat] = [:]
    @State private var bases: [String: CGFloat] = [:]
    @State private var pictures: [String: UIImage] = [:]
    @State private var failed: Set<String> = []
    @State private var share: AskCardExport?
    @State private var saveNote = ""
    @State private var showsSaveNote = false

    init(
        photos: [AskPhotosLine.Photo],
        startID: String,
        sourcePrefix: String,
        zoomID: Binding<String>
    ) {
        self.photos = photos
        self.startID = startID
        self.sourcePrefix = sourcePrefix
        _zoomID = zoomID
    }

    private var pageID: String {
        AskPhotosLine.selectedID(
            startID: startID,
            choiceStart: choiceStart,
            choiceID: choiceID,
            ids: photos.map(\.id)
        )
    }

    private var pageIndex: Int {
        photos.firstIndex { $0.id == pageID } ?? 0
    }

    private var current: AskPhotosLine.Photo? {
        photos.indices.contains(pageIndex) ? photos[pageIndex] : photos.first
    }

    private var currentScale: CGFloat {
        scales[pageID] ?? 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 0) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        AskPhotosPage(
                            photo: photo,
                            image: pictures[photo.id],
                            failed: failed.contains(photo.id),
                            position: index + 1,
                            count: photos.count,
                            scale: scaleBinding(photo.id),
                            base: baseBinding(photo.id)
                        )
                        .frame(width: width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(pageIndex) * width + (currentScale > 1 ? 0 : drag))
                .simultaneousGesture(paging)
            }
            if photos.count > 1 {
                VStack {
                    Spacer()
                    Text("\(pageIndex + 1) of \(photos.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 16)
                        .accessibilityHidden(true)
                }
                .allowsHitTesting(false)
            }
        }
        .task(id: pageID) {
            await loadAround(pageID)
        }
        .onChange(of: pageID) { _, id in
            zoomID = AskPhotosLine.zoomSource(prefix: sourcePrefix, photoID: id, ids: photos.map(\.id))
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy", systemImage: "doc.on.doc") { copyPicture() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", systemImage: "square.and.arrow.down") { savePicture() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share", systemImage: "square.and.arrow.up") { sharePicture() }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $share) { export in
            AskCardActivityView(items: export.items)
        }
        .alert("Photos", isPresented: $showsSaveNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveNote)
        }
    }

    private var paging: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard currentScale <= 1, photos.count > 1 else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                let travel = value.predictedEndTranslation.width
                var next = pageIndex
                if currentScale <= 1, photos.count > 1 {
                    if travel < -48 { next = min(pageIndex + 1, photos.count - 1) }
                    if travel > 48 { next = max(pageIndex - 1, 0) }
                }
                let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.28)
                withAnimation(animation) {
                    if photos.indices.contains(next) {
                        choiceStart = startID
                        choiceID = photos[next].id
                    }
                    drag = 0
                }
            }
    }

    private func scaleBinding(_ id: String) -> Binding<CGFloat> {
        Binding(get: { scales[id] ?? 1 }, set: { scales[id] = $0 })
    }

    private func baseBinding(_ id: String) -> Binding<CGFloat> {
        Binding(get: { bases[id] ?? 1 }, set: { bases[id] = $0 })
    }

    private func loadAround(_ id: String) async {
        let index = photos.firstIndex { $0.id == id } ?? 0
        let nearby = [index - 1, index, index + 1]
        for offset in nearby where photos.indices.contains(offset) {
            let photoID = photos[offset].id
            guard pictures[photoID] == nil, !failed.contains(photoID) else { continue }
            let image = await AskPhotoLibraryImage.load(
                photoID,
                points: 900,
                scale: displayScale,
                quality: .screen
            )
            if Task.isCancelled { return }
            if let image {
                pictures[photoID] = image
            } else {
                failed.insert(photoID)
            }
        }
    }

    private func copyPicture() {
        guard let picture = pictures[pageID] else { return }
        AskImageActions.copy(picture)
        AskCue.tap()
    }

    private func sharePicture() {
        guard let picture = pictures[pageID] else { return }
        AskCue.tap()
        share = AskCardExport(items: [picture])
    }

    private func savePicture() {
        guard let picture = pictures[pageID] else { return }
        AskCue.tap()
        Task {
            if let message = await AskImageActions.save(picture) {
                saveNote = message
                showsSaveNote = true
            }
        }
    }
}

private struct AskPhotosPage: View {
    var photo: AskPhotosLine.Photo
    var image: UIImage?
    var failed: Bool
    var position: Int
    var count: Int
    @Binding var scale: CGFloat
    @Binding var base: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(zoom)
                    .onTapGesture(count: 2) {
                        base = 1
                        scale = 1
                    }
                    .padding(24)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(count > 1 ? "\(photo.caption), \(position) of \(count)" : photo.caption)
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(base * value.magnification, 1), 4)
            }
            .onEnded { value in
                let next = min(max(base * value.magnification, 1), 4)
                base = next
                scale = next
            }
    }
}

enum AskPhotoLibraryImage {
    enum Quality {
        case thumbnail
        case screen
    }

    @MainActor
    static func load(
        _ localIdentifier: String,
        points: CGFloat,
        scale: CGFloat,
        quality: Quality
    ) async -> UIImage? {
        let trimmed = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [trimmed], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let cap: CGFloat = quality == .thumbnail ? 480 : 2400
        let pixels = min(max(points, 48) * max(scale, 1), cap)
        let target = CGSize(width: pixels, height: pixels)
        let options = PHImageRequestOptions()
        options.deliveryMode = quality == .thumbnail ? .fastFormat : .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            let once = AskPhotoResume()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: quality == .thumbnail ? .aspectFill : .aspectFit,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                once.finish(continuation, image: cancelled ? nil : image)
            }
        }
    }
}

private final class AskPhotoResume: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ continuation: CheckedContinuation<UIImage?, Never>, image: UIImage?) {
        lock.lock()
        let first = !finished
        finished = true
        lock.unlock()
        guard first else { return }
        continuation.resume(returning: image)
    }
}
