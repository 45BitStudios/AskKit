#if DEBUG
import SwiftUI

struct AskTraceSpanDetailView: View {
    @ObservedObject var viewModel: AskTraceViewModel
    let turnID: UUID
    let spanID: UUID

    var body: some View {
        List {
            if let span = viewModel.span(spanID, in: turnID) {
                overview(span)
                if let result = span.result { Section("Result") { code(result) } }
                let decisions = span.events.filter { $0.kind == .decision }
                if !decisions.isEmpty {
                    Section("Decisions") {
                        ForEach(Array(decisions.enumerated()), id: \.offset) { _, event in
                            eventRow(event, symbol: "arrow.triangle.branch", tint: Color(.systemPurple))
                        }
                    }
                }
                if !span.attributes.isEmpty {
                    Section("Attributes") {
                        ForEach(Array(span.attributes.enumerated()), id: \.offset) { _, attribute in
                            LabeledContent(attribute.key) {
                                Text(attribute.value).textSelection(.enabled)
                            }
                        }
                    }
                }
                let logs = span.events.filter { $0.kind != .decision }
                if !logs.isEmpty {
                    Section("Events") {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, event in
                            eventRow(event, symbol: "text.alignleft", tint: .secondary)
                        }
                    }
                }
                engineering(span)
                if let model = span.model {
                    modelSections(model)
                } else if let inlined = inlinedModelChild(of: span), let model = inlined.model {
                    modelSections(model)
                }
            } else {
                ContentUnavailableView("Span not found", systemImage: "questionmark")
            }
        }
        .navigationTitle(viewModel.span(spanID, in: turnID)?.name ?? "Span")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Same-name model child folded into a function row in Tree / Timeline.
    private func inlinedModelChild(of span: AskTraceSpan) -> AskTraceSpan? {
        guard span.kind == .function, let turn = viewModel.turn(turnID) else { return nil }
        let models = turn.spans.filter {
            $0.parentID == span.id && $0.kind == .model && $0.name == span.name
        }
        return models.count == 1 ? models[0] : nil
    }

    private func overview(_ span: AskTraceSpan) -> some View {
        Section {
            LabeledContent("Kind") {
                Label(span.kind.rawValue, systemImage: AskTraceFormatter.kindSymbol(span.kind))
            }
            LabeledContent("Started", value: "+\(AskTraceFormatter.duration(span.start))")
            LabeledContent("Duration", value: AskTraceFormatter.duration(span.duration))
            if let status = AskTraceFormatter.statusText(span.status) {
                LabeledContent("Status") { Text(status).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
    }

    private func engineering(_ span: AskTraceSpan) -> some View {
        Section {
            DisclosureGroup("For engineering") {
                LabeledContent("Function") {
                    Text(span.function).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
                LabeledContent("Source") {
                    Text("\(span.fileID):\(span.line)").font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }

    private func eventRow(_ event: AskTraceEvent, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind == .decision ? AskTraceFormatter.decisionWords(event.message) : event.message)
                    .font(.footnote)
                    .textSelection(.enabled)
                Text("+\(AskTraceFormatter.duration(event.offset))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modelSections(_ model: AskTraceModelCall) -> some View {
        let prompts = model.items.filter { $0.kind == .prompt }
        let setup = model.items.filter { $0.kind == .instructions || $0.kind == .toolDefinitions }
        let exchange = model.items.filter { item in
            switch item.kind {
            case .prompt, .instructions, .toolDefinitions: return false
            case .toolCall, .toolOutput, .response, .reasoning: return true
            }
        }
        transcriptSections(prompts)
        if let output = model.output { Section("Generated output") { code(output) } }
        if let errorDescription = model.errorDescription { Section("Error detail") { code(errorDescription) } }
        transcriptSections(exchange)
        transcriptSections(setup)
        Section("Foundation Models") {
            LabeledContent("Call", value: model.label)
            if let prewarmed = model.prewarmed {
                LabeledContent("Prewarmed session", value: prewarmed ? "yes" : "no")
            }
            if let errorKind = model.errorKind {
                LabeledContent("Error") { Text(errorKind).foregroundStyle(.red) }
            }
        }
        if let context = model.context { contextSection(context) }
    }

    @ViewBuilder
    private func transcriptSections(_ items: [AskTraceTranscriptItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Section(AskTraceFormatter.transcriptTitle(item)) { code(item.text) }
        }
    }

    private func contextSection(_ usage: AskTraceContextUsage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(1, usage.fraction))
                    .tint(AskTraceStyle.color(AskTraceFormatter.contextLevel(usage)))
                Text(AskTraceFormatter.contextSummary(usage)).font(.footnote.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            LabeledContent("Remaining", value: "\(AskTraceFormatter.tokens(usage.remainingTokens)) tokens")
            if let input = usage.inputTokens { LabeledContent("Input", value: AskTraceFormatter.tokens(input)) }
            if let cached = usage.cachedInputTokens { LabeledContent("Cached input", value: AskTraceFormatter.tokens(cached)) }
            if let output = usage.outputTokens { LabeledContent("Output", value: AskTraceFormatter.tokens(output)) }
            if let reasoning = usage.reasoningTokens { LabeledContent("Reasoning", value: AskTraceFormatter.tokens(reasoning)) }
            LabeledContent("Source", value: AskTraceFormatter.contextSourceText(usage.source))
        } header: {
            Text("Context window")
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
