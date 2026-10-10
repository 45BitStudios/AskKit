import Foundation
import FoundationModels
import LinkPresentation

/// The title and summary of one web page. A question that contains an https address can use it.
enum AskWebMetadata {
    static let toolName = "web"
    static let specialistID = "web"

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

    static func allowed(_ url: URL) -> Bool {
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
        if title.isEmpty {
            title = await linkTitle(url) ?? ""
        }
        return lines(title: title, page: url.absoluteString, summary: summary)
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
