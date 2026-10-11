#if DEBUG
import Foundation

enum AskTraceFormatter {
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        if seconds < 0.001 { return "<1 ms" }
        if seconds < 1 { return "\(Int((seconds * 1000).rounded())) ms" }
        return String(format: "%.2f s", seconds)
    }

    /// Compact wall time for the chat pill, such as `8s` or `2m 11s`.
    static func workedDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        if seconds < 1 { return "<1s" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes == 0 { return "\(secs)s" }
        if secs == 0 { return "\(minutes)m" }
        return "\(minutes)m \(secs)s"
    }

    /// Tool calls when any ran; otherwise model calls. Matches the chat pill's step count.
    static func workedSteps(toolCalls: Int, modelCalls: Int) -> Int {
        toolCalls > 0 ? toolCalls : modelCalls
    }

    static func workedCaption(duration: TimeInterval?, toolCalls: Int, modelCalls: Int) -> String {
        let steps = workedSteps(toolCalls: toolCalls, modelCalls: modelCalls)
        let stepLabel = steps == 1 ? "1 step" : "\(steps) steps"
        return "Worked \(workedDuration(duration)) · \(stepLabel)"
    }

    static func workedSymbol(toolCalls: Int) -> String {
        toolCalls > 0 ? kindSymbol(.tool) : "doc.text"
    }

    enum ContextLevel: Equatable {
        case normal
        case high
        case critical
    }

    static func contextLevel(_ usage: AskTraceContextUsage) -> ContextLevel {
        if usage.source == .contextExceeded || usage.fraction >= 0.9 { return .critical }
        return usage.fraction >= 0.75 ? .high : .normal
    }

    static func tokens(_ count: Int) -> String {
        tokenFormatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func contextBadge(_ usage: AskTraceContextUsage) -> String {
        "ctx \(percent(usage.fraction))"
    }

    static func contextSummary(_ usage: AskTraceContextUsage) -> String {
        "\(tokens(usage.usedTokens)) / \(tokens(usage.contextSize)) tokens (\(percent(usage.fraction)))"
    }

    static func contextBreakdown(_ usage: AskTraceContextUsage) -> String? {
        var parts: [String] = []
        if let input = usage.inputTokens {
            parts.append("input \(tokens(input))" + (usage.cachedInputTokens.map { " (cached \(tokens($0)))" } ?? ""))
        }
        if let output = usage.outputTokens {
            parts.append("output \(tokens(output))" + (usage.reasoningTokens.map { " (reasoning \(tokens($0)))" } ?? ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func contextSourceText(_ source: AskTraceContextUsage.Source) -> String {
        switch source {
        case .responseUsage: return "Response usage (exact)"
        case .contextExceeded: return "Context window exceeded"
        }
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter
    }()

    static func entrySymbol(_ entry: AskTraceEntry) -> String {
        switch entry.rawValue {
        case "chip": return "tag"
        case "siri": return "waveform"
        case "voice": return "mic"
        case "shortcut": return "square.grid.2x2"
        case "composer": return "bubble.left.and.text.bubble.right"
        default: return "questionmark.circle"
        }
    }

    static func kindSymbol(_ kind: AskTraceSpanKind) -> String {
        switch kind {
        case .turn: return "flag"
        case .function: return "function"
        case .model: return "brain"
        case .tool: return "wrench.and.screwdriver"
        case .userWait: return "pause.circle"
        }
    }

    static func statusText(_ status: AskTraceSpan.Status) -> String? {
        switch status {
        case .ok: return nil
        case .threw(let error): return "threw \(error)"
        case .unfinished: return "unfinished"
        }
    }

    static func transcriptTitle(_ item: AskTraceTranscriptItem) -> String {
        switch item.kind {
        case .instructions: return "Instructions"
        case .toolDefinitions: return "Tools available"
        case .prompt: return "Prompt"
        case .toolCall: return "Tool call → \(item.toolName ?? "?")"
        case .toolOutput: return "Tool output ← \(item.toolName ?? "?")"
        case .response: return "Response"
        case .reasoning: return "Reasoning"
        }
    }

    static func exportText(_ turn: AskTraceTurn) -> String {
        let date = ISO8601DateFormatter().string(from: turn.startedAt)
        var lines = ["Ask trace · \(turn.entry.rawValue) · \"\(turn.question)\" · \(date) · \(duration(turn.duration))", ""]
        func walk(_ nodes: [AskTraceNode], depth: Int) {
            for node in nodes {
                let span = node.span
                let indent = String(repeating: "  ", count: depth)
                var line = "\(indent)\(marker(span.kind)) \(span.name)  \(duration(span.duration))"
                if let result = span.result { line += "  → \(result)" }
                if let status = statusText(span.status) { line += "  [\(status)]" }
                lines.append(line)
                for attribute in span.attributes {
                    lines.append("\(indent)    \(attribute.key)=\(attribute.value)")
                }
                for event in span.events {
                    let message = event.kind == .decision ? decisionWords(event.message) : event.message
                    lines.append("\(indent)    \(event.kind == .decision ? "◆" : "·") \(message)")
                }
                if let model = span.model {
                    for item in model.items {
                        lines.append("\(indent)    [\(transcriptTitle(item))]")
                        lines.append(contentsOf: item.text.split(separator: "\n", omittingEmptySubsequences: false).map { "\(indent)      \($0)" })
                    }
                    if let output = model.output { lines.append("\(indent)    [Output] \(output)") }
                    if let context = model.context {
                        let breakdown = contextBreakdown(context).map { " · \($0)" } ?? ""
                        lines.append("\(indent)    [Context] \(contextSummary(context))\(breakdown) · \(contextSourceText(context.source))")
                    }
                    if let error = model.errorDescription {
                        lines.append("\(indent)    [Error \(model.errorKind ?? "")] \(error)")
                    }
                }
                walk(node.children, depth: depth + 1)
            }
        }
        walk(AskTraceViewModel.buildTree(spans: turn.spans), depth: 0)
        return lines.joined(separator: "\n")
    }

    private static func marker(_ kind: AskTraceSpanKind) -> String {
        switch kind {
        case .turn: return "▶"
        case .function: return "▸"
        case .model: return "🧠"
        case .tool: return "🔧"
        case .userWait: return "⏸"
        }
    }

    struct StoryLine: Equatable {
        var title: String
        var text: String
        var cards: [AskTracePosterCard] = []
    }

    static func listSentence(for turn: AskTraceTurn) -> String {
        var parts = [entryWords(turn.entry)]
        if let via = lastAttribute("routedVia", in: turn) {
            parts.append(routeWords(via))
        }
        if let skill = lastAttribute("skill", in: turn) {
            parts.append(skill)
        }
        parts.append(duration(turn.duration))
        return parts.joined(separator: " · ")
    }

    static func story(for turn: AskTraceTurn) -> [StoryLine] {
        var lines = [
            StoryLine(title: "Asked", text: turn.question),
            StoryLine(title: "From", text: entryWords(turn.entry))
        ]
        if let domain = lastAttribute("domain", in: turn) {
            lines.append(StoryLine(title: "Domain", text: domain))
        }
        if let skill = lastAttribute("skill", in: turn) {
            lines.append(StoryLine(title: "Skill", text: skill))
        }
        if let via = lastAttribute("routedVia", in: turn) {
            lines.append(StoryLine(title: "Routed via", text: routeSentence(via)))
        }
        lines.append(StoryLine(title: "Model calls", text: modelCallLine(in: turn)))
        if let sent = sentQuestion(in: turn), sent != turn.question.trimmingCharacters(in: .whitespacesAndNewlines) {
            lines.append(StoryLine(title: "Sent to the model", text: sent))
        }
        lines.append(StoryLine(
            title: "They heard",
            text: firstAttribute("shownAnswer", in: turn) ?? "It was not recorded."
        ))
        let cards = AskTracePoster.content(for: turn).cards
        lines.append(StoryLine(
            title: "Snippet",
            text: cards.isEmpty ? "No snippet card." : "",
            cards: cards
        ))
        for decision in storyDecisions(in: turn) {
            lines.append(StoryLine(title: "Why this path", text: decision))
        }
        lines.append(StoryLine(title: "How long", text: howLong(for: turn)))
        let problems = problemLines(in: turn)
        if !problems.isEmpty {
            lines.append(StoryLine(title: "What went wrong", text: problems.joined(separator: "\n")))
        }
        return lines
    }

    static func entryWords(_ entry: AskTraceEntry) -> String {
        switch entry.rawValue {
        case "composer": return "Composer"
        case "chip": return "Suggestion chip"
        case "shortcut": return "Shortcut"
        case "siri": return "Siri"
        case "voice": return "Microphone"
        default: return entry.rawValue
        }
    }

    static func routeWords(_ raw: String) -> String {
        switch raw {
        case "chip": return "Suggestion chip"
        case "fastPath": return "Router skipped"
        case "model": return "On-device model"
        case "fallback": return "Fallback"
        case "capabilities": return "Capabilities"
        case "guardrail": return "Guardrail"
        default: return raw
        }
    }

    /// Story wording. A fast path still leaves room for a specialist model call.
    static func routeSentence(_ raw: String) -> String {
        switch raw {
        case "fastPath":
            return "Router skipped. The skill was chosen without a router model."
        case "model":
            return "A router model chose the skill."
        case "chip":
            return "A suggestion chip chose the skill."
        case "fallback":
            return "Routing failed, so the fallback skill was used."
        case "capabilities":
            return "The question asked what the assistant can do."
        case "guardrail":
            return "The router was blocked, so the capabilities reply was used."
        default:
            return raw
        }
    }

    static func decisionWords(_ message: String) -> String {
        switch message {
        case "fast path": return "Router skipped"
        case "joined to the previous question": return "Joined onto the previous question"
        default: return message
        }
    }

    private static func firstAttribute(_ key: String, in turn: AskTraceTurn) -> String? {
        attributeValues(key, in: turn).first
    }

    private static func lastAttribute(_ key: String, in turn: AskTraceTurn) -> String? {
        attributeValues(key, in: turn).last
    }

    private static func attributeValues(_ key: String, in turn: AskTraceTurn) -> [String] {
        turn.spans.flatMap { span in
            span.attributes.compactMap { attribute in
                guard attribute.key == key else { return nil }
                let trimmed = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    private static func decisionMessages(in turn: AskTraceTurn) -> [String] {
        turn.spans.flatMap { span in
            span.events.filter { $0.kind == .decision }.map(\.message)
        }
    }

    /// The route line already says the router was skipped, so that decision is not repeated.
    private static func storyDecisions(in turn: AskTraceTurn) -> [String] {
        decisionMessages(in: turn).compactMap { message in
            guard message != "fast path" else { return nil }
            return decisionWords(message)
        }
    }

    private static func modelCallLine(in turn: AskTraceTurn) -> String {
        let names = turn.spans.filter { $0.kind == .model }.map(\.name)
        return names.isEmpty ? "No model call." : names.joined(separator: "\n")
    }

    /// The question the specialist received. A follow-up keeps the previous question in front.
    private static func sentQuestion(in turn: AskTraceTurn) -> String? {
        if let recorded = firstAttribute("promptQuestion", in: turn) {
            return recorded
        }
        for span in turn.spans {
            guard let items = span.model?.items else { continue }
            for item in items where item.kind == .prompt {
                if let question = questionBlock(in: item.text) {
                    return question
                }
            }
        }
        return nil
    }

    private static func questionBlock(in prompt: String) -> String? {
        let marker = "QUESTION\n"
        guard let start = prompt.range(of: marker) else { return nil }
        let rest = prompt[start.upperBound...]
        let end = rest.range(of: "\n\n")
        let block = end.map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func howLong(for turn: AskTraceTurn) -> String {
        var text = duration(turn.duration)
        let modelTime = turn.spans.reduce(into: 0.0) { total, span in
            guard span.kind == .model, let spanDuration = span.duration, spanDuration > 0 else { return }
            total += spanDuration
        }
        if let turnDuration = turn.duration, turnDuration > 0, modelTime > turnDuration / 2 {
            text += ". The on-device model took \(duration(modelTime)) of that."
        }
        if let peak = peakContext(in: turn) {
            if peak.source == .contextExceeded {
                text += " The on-device model ran out of room in its context window."
            } else if contextLevel(peak) != .normal {
                text += " The on-device model used \(percent(peak.fraction)) of its context window."
            }
        }
        return text
    }

    private static func peakContext(in turn: AskTraceTurn) -> AskTraceContextUsage? {
        var peak: AskTraceContextUsage?
        for span in turn.spans {
            guard let context = span.model?.context else { continue }
            if context.fraction > (peak?.fraction ?? -1) { peak = context }
        }
        return peak
    }

    private static func problemLines(in turn: AskTraceTurn) -> [String] {
        turn.spans.compactMap { span in
            guard case .threw(let error) = span.status else { return nil }
            let who: String
            switch span.kind {
            case .model: who = "The on-device model"
            case .tool: who = "A tool"
            case .userWait: who = "The wait"
            case .turn, .function: who = "A step"
            }
            return "\(who) failed: \(error)"
        }
    }
}
#endif
