#if ASK_FOUNDATION_MODELS
import Foundation
import FoundationModels

/// Every AskKit `LanguageModelSession.respond` goes through these so a debug trace gets a `.model` span.
/// The transcript is read after the call returns or throws, so token accounting is not part of the measured time.
extension AskTrace {
    static func respond<Content: Generable>(
        _ session: LanguageModelSession,
        label: String,
        to prompt: String,
        generating type: Content.Type,
        options: GenerationOptions = GenerationOptions(),
        prewarmed: Bool? = nil,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line
    ) async throws -> LanguageModelSession.Response<Content> {
        #if DEBUG
        var modelSpan: AskTraceContext?
        do {
            let response = try await span(label, kind: .model, function: function, fileID: fileID, line: line) {
                modelSpan = current
                return try await session.respond(to: prompt, generating: type, options: options)
            }
            recordModelCall(
                modelSpan,
                session: session,
                label: label,
                prewarmed: prewarmed,
                output: response.rawContent.jsonString,
                usage: contextUsage(of: response),
                error: nil
            )
            return response
        } catch {
            recordModelCall(modelSpan, session: session, label: label, prewarmed: prewarmed, output: nil, usage: nil, error: error)
            throw error
        }
        #else
        _ = (label, prewarmed, function, fileID, line)
        return try await session.respond(to: prompt, generating: type, options: options)
        #endif
    }

    static func respond(
        _ session: LanguageModelSession,
        label: String,
        to prompt: String,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line
    ) async throws -> LanguageModelSession.Response<String> {
        #if DEBUG
        var modelSpan: AskTraceContext?
        do {
            let response = try await span(label, kind: .model, function: function, fileID: fileID, line: line) {
                modelSpan = current
                return try await session.respond(to: prompt)
            }
            recordModelCall(
                modelSpan,
                session: session,
                label: label,
                prewarmed: nil,
                output: response.content,
                usage: contextUsage(of: response),
                error: nil
            )
            return response
        } catch {
            recordModelCall(modelSpan, session: session, label: label, prewarmed: nil, output: nil, usage: nil, error: error)
            throw error
        }
        #else
        _ = (label, function, fileID, line)
        return try await session.respond(to: prompt)
        #endif
    }

    /// Streams a plain reply. Each snapshot is the text so far. The returned string is the final text.
    static func respondStream(
        _ session: LanguageModelSession,
        label: String,
        to prompt: String,
        images: [URL] = [],
        attributes: [String: String] = [:],
        onSnapshot: @escaping @Sendable (String) async -> Void,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line
    ) async throws -> String {
        let stream: LanguageModelSession.ResponseStream<String>
        if images.isEmpty {
            stream = session.streamResponse(to: prompt)
        } else {
            let pictured = Prompt {
                prompt
                for url in images {
                    Attachment(imageURL: url).label("Image")
                }
            }
            stream = session.streamResponse(to: pictured)
        }
        #if DEBUG
        var modelSpan: AskTraceContext?
        var latest = ""
        var usage: LanguageModelSession.Usage?
        do {
            let text = try await span(label, kind: .model, function: function, fileID: fileID, line: line) {
                modelSpan = current
                for (key, value) in attributes {
                    AskTrace.attribute(key, value)
                }
                for try await snapshot in stream {
                    latest = snapshot.content
                    usage = snapshot.usage
                    await onSnapshot(latest)
                }
                return latest
            }
            recordModelCall(
                modelSpan,
                session: session,
                label: label,
                prewarmed: nil,
                output: text,
                usage: usage.map(contextUsage),
                error: nil
            )
            return text
        } catch {
            recordModelCall(modelSpan, session: session, label: label, prewarmed: nil, output: latest.isEmpty ? nil : latest, usage: usage.map(contextUsage), error: error)
            throw error
        }
        #else
        _ = (label, attributes, function, fileID, line)
        var latest = ""
        for try await snapshot in stream {
            latest = snapshot.content
            await onSnapshot(latest)
        }
        return latest
        #endif
    }

    /// Wraps a tool body in a `.tool` span. Foundation Models may call the tool off the turn's task.
    /// The span then attaches to the newest open model span.
    nonisolated(nonsending) public static func tool(
        _ name: String,
        arguments: @autoclosure () -> String,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line,
        _ body: nonisolated(nonsending) () async throws -> String
    ) async throws -> String {
        try await span("tool \(name)", kind: .tool, ["arguments": arguments()], function: function, fileID: fileID, line: line) {
            let output = try await body()
            result(output)
            return output
        }
    }
}

#if DEBUG
extension AskTrace {
    private static func recordModelCall(
        _ modelSpan: AskTraceContext?,
        session: LanguageModelSession,
        label: String,
        prewarmed: Bool?,
        output: String?,
        usage: AskTraceContextUsage?,
        error: Error?
    ) {
        guard let modelSpan else { return }
        var context = usage
        if context == nil {
            context = exceededUsage(error)
        }
        recorder.attachModel(modelSpan, call: AskTraceModelCall(
            label: label,
            prewarmed: prewarmed,
            items: transcriptItems(session.transcript),
            output: output,
            errorKind: error.map(errorKind),
            errorDescription: error.map { String(describing: $0) },
            context: context
        ))
    }

    private static func contextUsage<Content>(of response: LanguageModelSession.Response<Content>) -> AskTraceContextUsage {
        contextUsage(response.usage)
    }

    private static func contextUsage(_ usage: LanguageModelSession.Usage) -> AskTraceContextUsage {
        AskTraceContextUsage(
            source: .responseUsage,
            contextSize: SystemLanguageModel.default.contextSize,
            usedTokens: usage.totalTokenCount,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount,
            reasoningTokens: usage.output.reasoningTokenCount
        )
    }

    private static func exceededUsage(_ error: Error?) -> AskTraceContextUsage? {
        guard let modelError = error as? LanguageModelError,
              case .contextSizeExceeded(let exceeded) = modelError else {
            return nil
        }
        return AskTraceContextUsage(
            source: .contextExceeded,
            contextSize: exceeded.contextSize,
            usedTokens: exceeded.tokenCount
        )
    }

    static func transcriptItems(_ transcript: Transcript) -> [AskTraceTranscriptItem] {
        transcript.flatMap { entry -> [AskTraceTranscriptItem] in
            switch entry {
            case .instructions(let instructions):
                var items = [AskTraceTranscriptItem(kind: .instructions, toolName: nil, text: text(instructions.segments))]
                if !instructions.toolDefinitions.isEmpty {
                    let tools = instructions.toolDefinitions.map { "\($0.name): \($0.description)" }.joined(separator: "\n")
                    items.append(AskTraceTranscriptItem(kind: .toolDefinitions, toolName: nil, text: tools))
                }
                return items
            case .prompt(let prompt):
                return [AskTraceTranscriptItem(kind: .prompt, toolName: nil, text: text(prompt.segments))]
            case .toolCalls(let calls):
                return calls.map {
                    AskTraceTranscriptItem(kind: .toolCall, toolName: $0.toolName, text: $0.arguments.jsonString)
                }
            case .toolOutput(let output):
                return [AskTraceTranscriptItem(kind: .toolOutput, toolName: output.toolName, text: text(output.segments))]
            case .response(let response):
                return [AskTraceTranscriptItem(kind: .response, toolName: nil, text: text(response.segments))]
            case .reasoning(let reasoning):
                return [AskTraceTranscriptItem(kind: .reasoning, toolName: nil, text: text(reasoning.segments))]
            @unknown default:
                return [AskTraceTranscriptItem(kind: .response, toolName: nil, text: String(describing: entry))]
            }
        }
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                return text.content
            case .structure(let structure):
                return structure.content.jsonString
            case .attachment:
                return "[attachment]"
            @unknown default:
                return String(describing: segment)
            }
        }
        .joined(separator: "\n")
    }

    private static func errorKind(_ error: Error) -> String {
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded: return "contextSizeExceeded"
            case .rateLimited: return "rateLimited"
            case .guardrailViolation: return "guardrailViolation"
            case .refusal: return "refusal"
            case .unsupportedCapability: return "unsupportedCapability"
            case .unsupportedTranscriptContent: return "unsupportedTranscriptContent"
            case .unsupportedGenerationGuide: return "unsupportedGenerationGuide"
            case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
            case .timeout: return "timeout"
            @unknown default: return String(reflecting: type(of: modelError))
            }
        }
        if let cloud = error as? PrivateCloudComputeLanguageModel.Error {
            switch cloud {
            case .networkFailure: return "networkFailure"
            case .quotaLimitReached: return "quotaLimitReached"
            case .serviceUnavailable: return "serviceUnavailable"
            @unknown default: return String(reflecting: type(of: cloud))
            }
        }
        if error is GeneratedContent.ParsingError || error is GenerationSchema.SchemaError {
            return "schema"
        }
        if let assets = error as? SystemLanguageModel.Error {
            switch assets {
            case .assetsUnavailable: return "assetsUnavailable"
            @unknown default: return String(reflecting: type(of: assets))
            }
        }
        if let session = error as? LanguageModelSession.Error {
            switch session {
            case .concurrentRequests: return "concurrentRequests"
            case .transcriptMutationWhileResponding: return "transcriptMutationWhileResponding"
            @unknown default: return String(reflecting: type(of: session))
            }
        }
        return String(reflecting: type(of: error))
    }
}
#endif
#endif
