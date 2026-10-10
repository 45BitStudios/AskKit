import AskKit
import Foundation
import FoundationModels

/// Shared matching and lookup tools for sample host specialists.
enum SampleSpecialist {
    /// Words in the question, folded for English matching.
    nonisolated static func tokens(in question: String) -> [String] {
        question
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// True when any listed word appears as its own token.
    nonisolated static func matches(_ question: String, anyOf words: Set<String>) -> Bool {
        let folded = Set(words.map { $0.lowercased() })
        return tokens(in: question).contains { folded.contains($0) }
    }

    /// Builds a specialist that calls one lookup tool and speaks that line.
    nonisolated static func lookup(
        id: String,
        title: String,
        symbolName: String,
        workingTitle: String,
        toolName: String,
        toolDescription: String,
        result: String,
        words: Set<String>
    ) -> AskSpecialist {
        AskSpecialist(
            id: id,
            title: title,
            symbolName: symbolName,
            workingTitle: workingTitle,
            instructions: """
            Call the \(toolName) tool once and say what it returns. \
            If it says Not allowed, say you cannot see that. Do not invent a number or a name.
            """,
            tools: {
                [SampleLookupTool(name: toolName, description: toolDescription, result: result)]
            },
            matches: { matches($0, anyOf: words) }
        )
    }
}

/// Returns a fixed fact line. The line has no equals sign, so a reply can repeat it.
struct SampleLookupTool: Tool {
    let name: String
    let description: String
    let result: String

    @Generable
    struct Arguments {
        @Guide(description: "Leave empty.")
        var note: String?
    }

    func call(arguments: Arguments) async throws -> String {
        result
    }
}

/// The current time. The line has no equals sign, so a reply can repeat it.
struct SampleClockTool: Tool {
    let name = "clock"
    let description = "The current time on this device."

    @Generable
    struct Arguments {
        @Guide(description: "Leave empty.")
        var note: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        return "The time is \(time)."
    }
}
