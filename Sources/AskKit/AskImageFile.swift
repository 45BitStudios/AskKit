import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One image the composer will send with the next question.
package struct AskAttachedImage: Identifiable, Equatable, Sendable {
    package init(id: UUID = UUID(), url: URL, name: String) {
        self.id = id
        self.url = url
        self.name = name
    }

    package var id = UUID()
    package var url: URL
    package var name: String
}

/// Image files Foundation Models can attach. `Transcript.Attachment` has only an image case.
package enum AskImageFile {
    package static let maximumCount = 4

    /// JPEG, PNG, HEIC, HEIF, GIF, TIFF, BMP, WebP, AVIF, and JPEG 2000.
    package static let contentTypes: [UTType] = [
        .jpeg,
        .png,
        .gif,
        .tiff,
        .heic,
        UTType("public.heif"),
        UTType("com.microsoft.bmp"),
        UTType("org.webmproject.webp"),
        UTType("public.avif"),
        UTType("public.jpeg-2000")
    ].compactMap { $0 }

    static func matches(_ type: UTType) -> Bool {
        contentTypes.contains { type.conforms(to: $0) }
    }

    /// Writes a decoded image into Caches. Returns nil when ImageIO cannot read it or the type is not allowed.
    package static func store(data: Data, preferredName: String) -> URL? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeID = CGImageSourceGetType(source) as String?,
              let type = UTType(typeID),
              matches(type),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            return nil
        }
        return write(data, name: preferredName, type: type)
    }

    /// Copies a security-scoped file after the same image check.
    package static func storeCopy(of url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return store(data: data, preferredName: name.isEmpty ? "Image" : name)
    }

    private static func write(_ data: Data, name: String, type: UTType) -> URL? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AskKitImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = type.preferredFilenameExtension ?? "img"
            let base = (name as NSString).deletingPathExtension
            let stem = base.isEmpty ? "Image" : base
            let url = folder.appendingPathComponent("\(UUID().uuidString)-\(stem).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Date, place, camera, and coordinates read from an attached image file.
///
/// The reply prompt forbids stating anything that is not in FACTS, so this block is merged into FACTS.
/// A file with no readable metadata contributes nothing. Values never contain `=`.
package enum AskImageFacts {
    /// Appends photo lines to skill facts. Unchanged when the photo block is empty.
    static func merging(_ facts: String, photoFacts: String) -> String {
        guard !photoFacts.isEmpty else { return facts }
        let trimmed = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? photoFacts : trimmed + "\n" + photoFacts
    }

    /// Date, place, camera, pixel size, and a signed GPS coordinate from one file.
    struct Snapshot: Sendable, Equatable {
        var date: String?
        var place: String?
        var latitude: Double?
        var longitude: Double?
        var width: Int?
        var height: Int?
        var ppiWidth: Int?
        var ppiHeight: Int?
        var camera: String?

        init(
            date: String? = nil,
            place: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            width: Int? = nil,
            height: Int? = nil,
            ppiWidth: Int? = nil,
            ppiHeight: Int? = nil,
            camera: String? = nil
        ) {
            self.date = date
            self.place = place
            self.latitude = latitude
            self.longitude = longitude
            self.width = width
            self.height = height
            self.ppiWidth = ppiWidth
            self.ppiHeight = ppiHeight
            self.camera = camera
        }
    }

    /// A later message about that picture. "What location was it taken at" counts. "Where is Apple Park" does not.
    package static func continues(_ question: String) -> Bool {
        let folded = fold(question)
        if folded.localizedStandardContains("taken") { return true }
        if mentionsPixels(folded) { return true }
        if mentionsPicture(folded) { return true }
        if asksCamera(question) { return true }
        return asksDate(question)
    }

    /// Megapixels, resolution, or ppi. "mega ppi" counts.
    static func asksPixels(_ question: String) -> Bool {
        mentionsPixels(fold(question))
    }

    /// The question asked for ppi or dpi, not only the megapixel count.
    static func asksPPI(_ question: String) -> Bool {
        let folded = fold(question)
        return ["ppi", "dpi"].contains { folded.localizedStandardContains($0) }
    }

    /// What phone or camera made the picture. "With what phone" counts. "Where's my phone" does not.
    static func asksCamera(_ question: String) -> Bool {
        let folded = fold(question)
        let device = ["iphone", "phone", "camera", "model"].contains { folded.localizedStandardContains($0) }
        guard device else { return false }
        if asksPlace(folded), !folded.localizedStandardContains("taken"), !mentionsPicture(folded) {
            return false
        }
        if folded.localizedStandardContains("taken") || mentionsPicture(folded) { return true }
        if folded.localizedStandardContains("what type") || folded.localizedStandardContains("which") { return true }
        return folded.localizedStandardContains("what phone")
            || folded.localizedStandardContains("what camera")
            || folded.localizedStandardContains("which phone")
            || folded.localizedStandardContains("which camera")
            || folded.localizedStandardContains("with what")
    }

    /// When the picture was taken. "On what date" counts. "What's the date today" does not.
    static func asksDate(_ question: String) -> Bool {
        let folded = fold(question)
        if folded.localizedStandardContains("taken") || mentionsPicture(folded) {
            if folded.localizedStandardContains("date") || folded.localizedStandardContains("when") {
                return true
            }
        }
        return folded.localizedStandardContains("what date") || folded.localizedStandardContains("which date")
    }

    /// Where the attached picture was taken, not where the person is.
    static func asksWhereTaken(_ question: String) -> Bool {
        let folded = fold(question)
        guard asksPlace(folded) else { return false }
        return folded.localizedStandardContains("taken") || mentionsPicture(folded)
    }

    /// Place name when the file has one. Otherwise the date, and a clear line that the place is missing.
    static func whereTakenSentence(_ shots: [Snapshot]) -> String? {
        let named = shots.compactMap(\.place).filter { !$0.isEmpty && $0 != AskPhotoLocation.unnamed }
        if named.count == 1 {
            return "It was taken at \(named[0])."
        }
        if named.count > 1 {
            return named.enumerated().map { "Photo \($0.offset + 1) was taken at \($0.element)." }.joined(separator: " ")
        }
        if shots.contains(where: { $0.place == AskPhotoLocation.unnamed }) {
            return "The map shows where it was taken."
        }
        guard let date = shots.compactMap(\.date).first(where: { !$0.isEmpty }) else { return nil }
        let lead = shots.count > 1 ? "These photos don't include a place." : "This photo doesn't include a place."
        return "\(lead) It was taken on \(date)."
    }

    /// Megapixels from the pixel size. PPI is added only when the question asked for it.
    static func pixelSentence(_ shots: [Snapshot], includesPPI: Bool) -> String? {
        let sized = shots.enumerated().filter { ($0.element.width ?? 0) > 0 && ($0.element.height ?? 0) > 0 }
        guard !sized.isEmpty else { return nil }
        let lines = sized.map { item in
            let body = pixelBody(item.element, includesPPI: includesPPI)
            if sized.count == 1, shots.count == 1 { return "It's \(body)." }
            return "Photo \(item.offset + 1) is \(body)."
        }
        return lines.joined(separator: " ")
    }

    /// The camera recorded on the file. Nil when the question is not about the camera.
    static func cameraSentence(_ shots: [Snapshot]) -> String? {
        let names = shots.compactMap(\.camera).filter { !$0.isEmpty }
        if names.isEmpty { return "This photo doesn't include the camera." }
        if names.count == 1 { return "It was taken on \(article(names[0])) \(names[0])." }
        return names.enumerated().map { "Photo \($0.offset + 1) was taken on \(article($0.element)) \($0.element)." }.joined(separator: " ")
    }

    /// The clock stored on the file. An empty date says so instead of guessing.
    static func dateSentence(_ shots: [Snapshot]) -> String? {
        guard !shots.isEmpty else { return nil }
        if shots.count == 1 {
            if let date = shots[0].date, !date.isEmpty {
                return "It was taken on \(date)."
            }
            return "This photo doesn't include a date."
        }
        return shots.enumerated().map { index, shot in
            if let date = shot.date, !date.isEmpty {
                return "Photo \(index + 1) was taken on \(date)."
            }
            return "Photo \(index + 1) doesn't include a date."
        }.joined(separator: " ")
    }

    /// The photo fact this question asks for. Place wins when the words also name the camera or the date.
    enum PhotoAspect: Equatable {
        case place
        case pixels
        case camera
        case date
    }

    static func aspect(_ question: String) -> PhotoAspect? {
        if asksWhereTaken(question) { return .place }
        if asksPixels(question) { return .pixels }
        if asksCamera(question) { return .camera }
        if asksDate(question) { return .date }
        return nil
    }

    /// Every part asks about a picture, and they do not all ask the same thing.
    static func distinctQuestions(_ pieces: [String], hasPhotos: Bool) -> Bool {
        guard hasPhotos, pieces.count > 1 else { return false }
        let aspects = pieces.compactMap(aspect)
        guard aspects.count == pieces.count else { return false }
        return Set(aspects).count > 1
    }

    static func snapshots(_ urls: [URL]) -> [Snapshot] {
        urls.prefix(AskImageFile.maximumCount).compactMap { snapshot(at: $0) }
    }

    /// One line per photo that has file metadata, at most `AskImageFile.maximumCount`.
    static func block(_ urls: [URL]) -> String {
        let urls = Array(urls.prefix(AskImageFile.maximumCount))
        let lines = urls.enumerated().compactMap { offset, url in
            line(for: url, index: offset, count: urls.count)
        }
        var kept: [String] = []
        var count = 0
        for line in lines {
            let next = count + line.count + (kept.isEmpty ? 0 : 1)
            if !kept.isEmpty, next > blockLimit { break }
            kept.append(line)
            count = next
        }
        return kept.joined(separator: "\n")
    }

    private static let lineLimit = 240
    private static let blockLimit = 900

    private static func line(for url: URL, index: Int, count: Int) -> String? {
        guard let props = properties(at: url) else { return nil }
        let parts = details(in: props)
        guard !parts.isEmpty else { return nil }
        return sentence(label: label(for: url, index: index, count: count), parts: parts)
    }

    private static func details(in props: [String: Any]) -> [String] {
        let exif = nested(kCGImagePropertyExifDictionary, in: props)
        let tiff = nested(kCGImagePropertyTIFFDictionary, in: props)
        let iptc = nested(kCGImagePropertyIPTCDictionary, in: props)
        let gps = nested(kCGImagePropertyGPSDictionary, in: props)
        var parts: [String] = []
        if let taken = clock(in: exif, tiff: tiff, iptc: iptc) {
            parts.append("Taken \(taken)")
        }
        let place = unique([
            text(kCGImagePropertyIPTCSubLocation, in: iptc),
            text(kCGImagePropertyIPTCCity, in: iptc),
            text(kCGImagePropertyIPTCProvinceState, in: iptc),
            text(kCGImagePropertyIPTCCountryPrimaryLocationName, in: iptc)
        ].compactMap { $0 })
        if !place.isEmpty {
            parts.append("Place \(place.joined(separator: ", "))")
        }
        if let coordinates = coordinates(in: gps) {
            parts.append(coordinates)
        }
        if let altitude = altitude(in: gps) {
            parts.append(altitude)
        }
        if let camera = camera(in: tiff) {
            parts.append("Camera \(camera)")
        }
        if !parts.isEmpty, let width = integer(kCGImagePropertyPixelWidth, in: props),
           let height = integer(kCGImagePropertyPixelHeight, in: props),
           width > 0, height > 0 {
            var size = "Size \(width) by \(height)"
            if let count = megapixelCount(width: width, height: height) {
                size += ", \(count) megapixels"
            }
            parts.append(size)
            let pixels = resolution(in: tiff, props: props)
            if let ppi = ppiText(width: pixels.0, height: pixels.1) {
                parts.append(ppi)
            }
        }
        if let name = text(kCGImagePropertyIPTCObjectName, in: iptc) {
            parts.append("Name \(name)")
        }
        if let caption = text(kCGImagePropertyIPTCCaptionAbstract, in: iptc)
            ?? text(kCGImagePropertyTIFFImageDescription, in: tiff) {
            parts.append("Caption \(caption)")
        }
        if let keywords = keywords(in: iptc) {
            parts.append("Keywords \(keywords)")
        }
        return parts
    }

    private static func sentence(label: String, parts: [String]) -> String {
        var kept: [String] = []
        for part in parts {
            let clipped = clip(part)
            let body = (kept + [clipped]).joined(separator: ". ")
            if "\(label). \(body).".count > lineLimit, !kept.isEmpty { break }
            kept.append(clipped)
        }
        return "\(label). \(kept.joined(separator: ". "))."
    }

    private static func clip(_ part: String) -> String {
        guard part.count > 160 else { return part }
        return String(part.prefix(157)) + "..."
    }

    private static func label(for url: URL, index: Int, count: Int) -> String {
        let stem = fileStem(url)
        if count == 1 {
            return stem.map { "Photo \($0)" } ?? "Photo"
        }
        if let stem { return "Photo \(index + 1) \(stem)" }
        return "Photo \(index + 1)"
    }

    private static func fileStem(_ url: URL) -> String? {
        var stem = url.deletingPathExtension().lastPathComponent
        let storedName = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}-(.+)$/
        if let match = stem.wholeMatch(of: storedName) {
            stem = String(match.1)
        }
        let folded = stem.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        guard !stem.isEmpty, folded != "photo", folded != "image" else { return nil }
        return plain(stem)
    }

    private static func properties(at url: URL) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            return nil
        }
        return dictionary(raw)
    }

    private static func nested(_ key: CFString, in props: [String: Any]) -> [String: Any] {
        guard let raw = props[key as String] else { return [:] }
        return dictionary(raw) ?? [:]
    }

    private static func dictionary(_ raw: Any) -> [String: Any]? {
        if let props = raw as? [String: Any] { return props }
        guard let props = raw as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in props {
            if let name = key as? String {
                out[name] = value
            }
        }
        return out
    }

    private static func clock(in exif: [String: Any], tiff: [String: Any], iptc: [String: Any]) -> String? {
        if let raw = text(kCGImagePropertyExifDateTimeOriginal, in: exif) ?? text(kCGImagePropertyTIFFDateTime, in: tiff),
           let taken = taken(raw) {
            return taken
        }
        return iptcTaken(iptc)
    }

    /// ImageIO stores `yyyy:MM:dd HH:mm:ss` in the camera's local clock, with no zone.
    private static func taken(_ raw: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: String(raw.prefix(19))) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = TimeZone(secondsFromGMT: 0)
        out.dateFormat = "d MMMM yyyy 'at' h:mm a"
        return out.string(from: date)
    }

    private static func iptcTaken(_ iptc: [String: Any]) -> String? {
        guard let day = text(kCGImagePropertyIPTCDateCreated, in: iptc), day.count == 8 else { return nil }
        let clock = text(kCGImagePropertyIPTCTimeCreated, in: iptc) ?? "000000"
        guard clock.count >= 6 else { return nil }
        let raw = "\(day.prefix(4)):\(day.dropFirst(4).prefix(2)):\(day.suffix(2)) \(clock.prefix(2)):\(clock.dropFirst(2).prefix(2)):\(clock.dropFirst(4).prefix(2))"
        return taken(raw)
    }

    private static func snapshot(at url: URL) -> Snapshot? {
        guard let props = properties(at: url) else { return nil }
        let exif = nested(kCGImagePropertyExifDictionary, in: props)
        let tiff = nested(kCGImagePropertyTIFFDictionary, in: props)
        let iptc = nested(kCGImagePropertyIPTCDictionary, in: props)
        let gps = nested(kCGImagePropertyGPSDictionary, in: props)
        let placeParts = unique([
            text(kCGImagePropertyIPTCSubLocation, in: iptc),
            text(kCGImagePropertyIPTCCity, in: iptc),
            text(kCGImagePropertyIPTCProvinceState, in: iptc),
            text(kCGImagePropertyIPTCCountryPrimaryLocationName, in: iptc)
        ].compactMap { $0 })
        let pair = coordinatePair(in: gps)
        let pixels = resolution(in: tiff, props: props)
        let width = integer(kCGImagePropertyPixelWidth, in: props)
        let height = integer(kCGImagePropertyPixelHeight, in: props)
        let shot = Snapshot(
            date: clock(in: exif, tiff: tiff, iptc: iptc),
            place: placeParts.isEmpty ? nil : placeParts.joined(separator: ", "),
            latitude: pair?.0,
            longitude: pair?.1,
            width: (width ?? 0) > 0 ? width : nil,
            height: (height ?? 0) > 0 ? height : nil,
            ppiWidth: pixels.0,
            ppiHeight: pixels.1,
            camera: camera(in: tiff)
        )
        if shot.date == nil, shot.place == nil, shot.latitude == nil, shot.width == nil, shot.camera == nil {
            return nil
        }
        return shot
    }

    private static func mentionsPixels(_ folded: String) -> Bool {
        ["megapixel", "mega pixel", "mega ppi", "ppi", "dpi", "resolution", "pixel"].contains {
            folded.localizedStandardContains($0)
        }
    }

    private static func pixelBody(_ shot: Snapshot, includesPPI: Bool) -> String {
        let width = shot.width ?? 0
        let height = shot.height ?? 0
        let size = "\(width) by \(height)"
        let count = megapixelCount(width: width, height: height)
        var body = count.map { "\($0) megapixels, \(size)" } ?? size
        guard includesPPI else { return body }
        if let ppi = ppiText(width: shot.ppiWidth, height: shot.ppiHeight) {
            body += ", at \(ppi)"
        } else {
            body += ". The file doesn't include a ppi"
        }
        return body
    }

    /// Nil under a tenth of a megapixel, so a tiny test image does not claim 0.
    private static func megapixelCount(width: Int, height: Int) -> String? {
        let value = Double(width) * Double(height) / 1_000_000
        guard value >= 0.1 else { return nil }
        if abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func ppiText(width: Int?, height: Int?) -> String? {
        switch (width, height) {
        case let (wide?, high?) where abs(wide - high) <= 1:
            return "\(wide) ppi"
        case let (wide?, high?):
            return "\(wide) by \(high) ppi"
        case let (wide?, nil):
            return "\(wide) ppi"
        case let (nil, high?):
            return "\(high) ppi"
        default:
            return nil
        }
    }

    /// TIFF resolution, in pixels per inch. Centimeters are converted. A missing or 1-unit value is ignored.
    private static func resolution(in tiff: [String: Any], props: [String: Any]) -> (Int?, Int?) {
        let unit = integer(kCGImagePropertyTIFFResolutionUnit, in: tiff) ?? 2
        let x = number(kCGImagePropertyTIFFXResolution, in: tiff) ?? number(kCGImagePropertyDPIWidth, in: props)
        let y = number(kCGImagePropertyTIFFYResolution, in: tiff) ?? number(kCGImagePropertyDPIHeight, in: props)
        func points(_ value: Double?) -> Int? {
            guard let value, value > 1 else { return nil }
            let inches = unit == 3 ? value * 2.54 : value
            let rounded = Int(inches.rounded())
            return rounded > 1 ? rounded : nil
        }
        return (points(x), points(y))
    }

    private static func article(_ name: String) -> String {
        let first = name.first.map { String($0).lowercased() } ?? ""
        return ["a", "e", "i", "o", "u"].contains(first) ? "an" : "a"
    }

    private static func fold(_ question: String) -> String {
        question.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func asksPlace(_ folded: String) -> Bool {
        ["where", "location", "place"].contains { folded.localizedStandardContains($0) }
    }

    private static func mentionsPicture(_ folded: String) -> Bool {
        ["photo", "picture", "image", "camera"].contains { folded.localizedStandardContains($0) }
    }

    private static func coordinates(in gps: [String: Any]) -> String? {
        guard let pair = coordinatePair(in: gps) else { return nil }
        return String(format: "Coordinates %.4f, %.4f", pair.0, pair.1)
    }

    private static func coordinatePair(in gps: [String: Any]) -> (Double, Double)? {
        guard let latitude = number(kCGImagePropertyGPSLatitude, in: gps),
              let longitude = number(kCGImagePropertyGPSLongitude, in: gps) else {
            return nil
        }
        let latRef = (text(kCGImagePropertyGPSLatitudeRef, in: gps) ?? "").uppercased()
        let lonRef = (text(kCGImagePropertyGPSLongitudeRef, in: gps) ?? "").uppercased()
        let lat = latRef == "S" ? -abs(latitude) : abs(latitude)
        let lon = lonRef == "W" ? -abs(longitude) : abs(longitude)
        return (lat, lon)
    }

    private static func altitude(in gps: [String: Any]) -> String? {
        guard let meters = number(kCGImagePropertyGPSAltitude, in: gps) else { return nil }
        let below = integer(kCGImagePropertyGPSAltitudeRef, in: gps) == 1
        let rounded = String(format: "%.0f", abs(meters))
        return below ? "Altitude \(rounded) m below sea level" : "Altitude \(rounded) m"
    }

    private static func camera(in tiff: [String: Any]) -> String? {
        let make = text(kCGImagePropertyTIFFMake, in: tiff)
        let model = text(kCGImagePropertyTIFFModel, in: tiff)
        if let model, let make, model.range(of: make, options: .caseInsensitive) != nil {
            return model
        }
        if let make, let model { return "\(make) \(model)" }
        return model ?? make
    }

    private static func keywords(in iptc: [String: Any]) -> String? {
        let raw = iptc[kCGImagePropertyIPTCKeywords as String]
        let words: [String]
        if let list = raw as? [String] {
            words = list.compactMap(plain)
        } else if let list = raw as? [Any] {
            words = list.compactMap { item in
                (item as? String).flatMap(plain)
            }
        } else if let text = raw as? String, let word = plain(text) {
            words = [word]
        } else {
            words = []
        }
        let kept = words.prefix(6)
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }

    private static func unique(_ parts: [String]) -> [String] {
        var seen: [String] = []
        for part in parts {
            let folded = part.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            if seen.contains(where: { $0.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == folded }) {
                continue
            }
            seen.append(part)
        }
        return seen
    }

    private static func text(_ key: CFString, in props: [String: Any]) -> String? {
        switch props[key as String] {
        case let text as String:
            return plain(text)
        case let number as NSNumber:
            return plain(number.stringValue)
        default:
            return nil
        }
    }

    private static func number(_ key: CFString, in props: [String: Any]) -> Double? {
        switch props[key as String] {
        case let number as Double:
            return number
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func integer(_ key: CFString, in props: [String: Any]) -> Int? {
        switch props[key as String] {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    /// Drops `=` so a photo fact cannot fail the reply check, and keeps each value on one line.
    private static func plain(_ raw: String) -> String? {
        let collapsed = raw
            .replacingOccurrences(of: "=", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
