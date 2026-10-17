import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
import LinkPresentation
import SwiftUI

/// The title and summary of one web page. A question that contains an https address can use it.
package enum AskWebMetadata {
    static let toolName = "web"
    static let specialistID = "web"
    static let symbolName = "globe"

    static let note = """
    Call the web tool once and pass the https address from the question. \
    Say the title it returns. A summary may follow. If it says the page could not be read, say that. \
    Do not invent the title or the summary.
    """

    /// The first http or https address in the question.
    static func url(in question: String) -> URL? {
        let pieces = question.split { $0.isWhitespace || $0.isNewline }
        for piece in pieces {
            var token = String(piece)
            while let last = token.last, ".,);>\"'".contains(last) {
                token.removeLast()
            }
            guard let url = URL(string: token), allowed(url) else { continue }
            return url
        }
        return nil
    }

    package static func allowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Title and summary from a page's HTML. The summary prefers the description meta tag.
    static func text(in html: String) -> (title: String, summary: String) {
        let title = plain(tag("title", in: html) ?? meta(html, keys: ["og:title", "twitter:title"]) ?? "")
        let summary = plain(meta(html, keys: ["description", "og:description", "twitter:description"]) ?? "")
        return (clip(title, 120), clip(summary, 240))
    }

    /// Lines the model and the card both read. None of them contain an equals sign.
    static func lines(title: String, page: String, summary: String) -> String {
        var rows = [clip(plain(title), 120)]
        let address = clip(plain(page), 200)
        if !address.isEmpty {
            rows.append("Page: \(address)")
        }
        let about = clip(plain(summary), 240)
        if !about.isEmpty {
            rows.append(about)
        }
        let kept = rows.filter { !$0.isEmpty }
        return kept.isEmpty ? unread : kept.joined(separator: "\n")
    }

    static let unread = "That page could not be read."
    static let missingAddress = "A page address is needed."

    /// Fetches the page, then asks Link Presentation for a title when the HTML has none.
    static func read(urlString: String) async -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), allowed(url) else { return missingAddress }
        let html = await pageHTML(url)
        var (title, summary) = text(in: html)
        // The Page line is the card's lookup key. Image addresses stay out of the tool text.
        let shown = clip(plain(url.absoluteString), 200)
        await AskWebPictures.remember(pictures(in: html, page: url), for: shown)
        if title.isEmpty {
            title = await linkTitle(url) ?? ""
        }
        return lines(title: title, page: url.absoluteString, summary: summary)
    }

    /// The address line the card shows, without the "Page:" label.
    package static func pageAddress(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("page:") else { continue }
            let rest = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { continue }
            return rest
        }
        return nil
    }

    /// Preview image and site icon named in the page head. Relative links use the page address.
    static func pictures(in html: String, page: URL) -> AskWebPictures {
        let image = absolute(
            metaContent(html, names: ["og:image", "og:image:secure_url"])
                ?? metaContent(html, names: ["twitter:image"]),
            page: page
        )
        let icon = absolute(iconHref(in: html), page: page)
            ?? absolute("/favicon.ico", page: page)
        return AskWebPictures(page: page, image: image, icon: icon)
    }

    static func absolute(_ raw: String?, page: URL) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        guard let url = URL(string: text, relativeTo: page)?.absoluteURL, allowed(url) else { return nil }
        return url
    }

    private static func pageHTML(_ url: URL) async -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("AskKit", forHTTPHeaderField: "User-Agent")
        var data = Data()
        data.reserveCapacity(65_536)
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                bytes.task.cancel()
                return ""
            }
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 65_536 {
                    bytes.task.cancel()
                    break
                }
            }
        } catch {
            if data.isEmpty { return "" }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func linkTitle(_ url: URL) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url)
                let value = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (value?.isEmpty == false) ? value : nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            var title: String?
            for await value in group {
                if let value, !value.isEmpty {
                    title = value
                    break
                }
            }
            group.cancelAll()
            return title
        }
    }

    private static func tag(_ name: String, in html: String) -> String? {
        let folded = html.lowercased()
        let open = "<\(name)"
        guard let start = folded.range(of: open) else { return nil }
        guard let closeAngle = folded.range(of: ">", range: start.upperBound..<folded.endIndex) else { return nil }
        let endTag = "</\(name)>"
        guard let end = folded.range(of: endTag, range: closeAngle.upperBound..<folded.endIndex) else { return nil }
        return String(html[closeAngle.upperBound..<end.lowerBound])
    }

    private static func meta(_ html: String, keys: [String]) -> String? {
        let folded = html.lowercased()
        var search = folded.startIndex
        while let meta = folded.range(of: "<meta", range: search..<folded.endIndex) {
            guard let end = folded.range(of: ">", range: meta.upperBound..<folded.endIndex) else { return nil }
            let tag = String(html[meta.lowerBound..<end.upperBound])
            let foldedTag = tag.lowercased()
            if keys.contains(where: { foldedTag.contains($0) }), let content = content(in: tag) {
                return content
            }
            search = end.upperBound
        }
        return nil
    }

    /// A meta content value whose property or name is exactly one of `names`.
    private static func metaContent(_ html: String, names: [String]) -> String? {
        let wanted = Set(names.map { $0.lowercased() })
        let folded = html.lowercased()
        var search = folded.startIndex
        while let meta = folded.range(of: "<meta", range: search..<folded.endIndex) {
            guard let end = folded.range(of: ">", range: meta.upperBound..<folded.endIndex) else { return nil }
            let tag = String(html[meta.lowerBound..<end.upperBound])
            let property = quoted("property", in: tag).lowercased()
            let name = quoted("name", in: tag).lowercased()
            if wanted.contains(property) || wanted.contains(name), let value = content(in: tag) {
                return value
            }
            search = end.upperBound
        }
        return nil
    }

    /// Site icon from the head. A touch icon is preferred over a tiny favicon.
    private static func iconHref(in html: String) -> String? {
        let folded = html.lowercased()
        var search = folded.startIndex
        var touch: String?
        var icon: String?
        while let link = folded.range(of: "<link", range: search..<folded.endIndex) {
            guard let end = folded.range(of: ">", range: link.upperBound..<folded.endIndex) else { return touch ?? icon }
            let tag = String(html[link.lowerBound..<end.upperBound])
            let rel = quoted("rel", in: tag).lowercased()
            let href = quoted("href", in: tag)
            if !href.isEmpty {
                if rel.contains("apple-touch-icon"), touch == nil {
                    touch = href
                } else if rel == "icon" || rel.contains("shortcut icon"), icon == nil {
                    icon = href
                }
            }
            search = end.upperBound
        }
        return touch ?? icon
    }

    private static func quoted(_ name: String, in tag: String) -> String {
        let folded = tag.lowercased()
        guard let key = folded.range(of: name) else { return "" }
        let rest = tag[key.upperBound...]
        guard let equals = rest.firstIndex(of: "=") else { return "" }
        let after = rest[rest.index(after: equals)...].drop(while: \.isWhitespace)
        guard let quote = after.first, quote == "\"" || quote == "'" else { return "" }
        let start = after.index(after: after.startIndex)
        guard let end = after[start...].firstIndex(of: quote) else { return "" }
        return String(after[start..<end])
    }

    private static func content(in tag: String) -> String? {
        let folded = tag.lowercased()
        guard let key = folded.range(of: "content") else { return nil }
        let rest = tag[key.upperBound...]
        guard let quote = rest.first(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        guard let start = rest.firstIndex(of: quote) else { return nil }
        let after = rest.index(after: start)
        guard let end = rest[after...].firstIndex(of: quote) else { return nil }
        return String(rest[after..<end])
    }

    private static func plain(_ raw: String) -> String {
        var text = raw
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " "
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "=", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if ASK_FOUNDATION_MODELS
struct AskWebMetadataTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = AskWebMetadata.toolName
    let description = "Read the title and summary of one web page. Pass the https address from the question. Call once. If the result says the page could not be read, say that. Do not invent the title."

    @Generable
    struct Arguments {
        @Guide(description: "The https address copied from the question.")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "page") {
            await AskWebMetadata.read(urlString: arguments.url)
        }
    }
}
#endif

/// Preview image and site icon for one page. The tool text never carries these addresses.
package struct AskWebPictures: Sendable, Equatable {
    package var page: URL
    package var image: URL?
    package var icon: URL?

    /// Keeps the addresses for this process, under the Page line the card shows.
    static func remember(_ pictures: AskWebPictures, for address: String) async {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        await AskWebPictureIndex.shared.remember(pictures, for: key)
    }

    package static func pictures(for address: String) async -> AskWebPictures? {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return await AskWebPictureIndex.shared.pictures(for: key)
    }

    /// Image bytes from a page address. Nil when the response is not a small http image.
    package static func imageData(at url: URL) async -> Data? {
        guard AskWebMetadata.allowed(url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("AskKit", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let final = response.url, AskWebMetadata.allowed(final) else { return nil }
            guard data.count > 32, data.count <= 3_000_000 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Link Presentation image and icon. Used when the page named nothing, or the download failed.
    package static func presentation(for url: URL) async -> (image: Data?, icon: Data?) {
        guard AskWebMetadata.allowed(url) else { return (nil, nil) }
        let provider = LPMetadataProvider()
        provider.timeout = 5
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
            return (nil, nil)
        }
        let image = await file(from: metadata.imageProvider)
        let icon = await file(from: metadata.iconProvider)
        withExtendedLifetime(provider) {}
        return (image, icon)
    }

    private static func file(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: AskPlatformImage.self) { object, _ in
                let bytes = (object as? AskPlatformImage).flatMap(AskPlatform.pngData)
                continuation.resume(returning: bytes)
            }
        }
        guard let data, data.count > 32, data.count <= 3_000_000 else { return nil }
        return data
    }
}

/// Process-lifetime lookup from the shown Page line to the image addresses.
private actor AskWebPictureIndex {
    static let shared = AskWebPictureIndex()

    private var items: [String: AskWebPictures] = [:]
    private var order: [String] = []

    func remember(_ pictures: AskWebPictures, for address: String) {
        if items[address] == nil {
            order.append(address)
        }
        items[address] = pictures
        while order.count > 24, let oldest = order.first {
            order.removeFirst()
            if oldest != address {
                items[oldest] = nil
            }
        }
    }

    func pictures(for address: String) -> AskWebPictures? {
        items[address]
    }
}
