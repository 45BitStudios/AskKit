#if DEBUG
import AskKit
import AskKitIntents
import Foundation

enum AskTraceGuide {
    enum Symbol: Equatable {
        case entry(AskTraceEntry)
        case kind(AskTraceSpanKind)
        case system(String, Tint)
        case glyph(String)
        case contextBadge(AskTraceContextUsage)
    }

    enum Tint: Equatable {
        case accent
        case secondary
        case red
        case purple
    }

    struct Item: Identifiable, Equatable {
        var id: String { title }
        let symbol: Symbol?
        let title: String
        let detail: String
    }

    struct Section: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let items: [Item]
        var footer: String?
    }

    static let sections: [Section] = [
        Section(title: "What a trace is", items: [
            Item(symbol: nil, title: "One row per question", detail: "Each question from the composer, a chip, or an entry name the app passes is one turn."),
            Item(symbol: nil, title: "Only traced steps appear", detail: "AskKit records context, follow-up stitching, domain and skill routing, slot filling, and the reply. A parent's time can be larger than its children."),
            Item(symbol: .system("rectangle.stack", .accent), title: "Snippet", detail: "The Story tab shows the cards from that answer. A turn with no card says no snippet card.")
        ]),
        Section(title: "Where the question came from", items: [
            Item(symbol: .entry(.composer), title: "Composer", detail: "A question typed in the chat. The default entry."),
            Item(symbol: .entry(.chip), title: "Suggestion chip", detail: "A chip tap. No model session is opened to choose the skill."),
            Item(symbol: .entry(.shortcut), title: "Shortcut", detail: "AskIntent, or a host intent that calls AskIntent.answer. The registered client can change this entry."),
            Item(symbol: .entry(.siri), title: "Siri", detail: "A host that passes AskTraceEntry.siri."),
            Item(symbol: .entry(.voice), title: "Voice", detail: "Listen until the person pauses, then Ask speaks the answer. Not Siri."),
            Item(symbol: .entry(.toolkit), title: "Card toolkit", detail: "A scenario from the card toolkit. The model lays out the card, or the fact layout is used when compose fails."),
            Item(symbol: .system("questionmark.circle", .secondary), title: "Any other name", detail: "A host can pass its own entry. The raw value is what the list shows.")
        ]),
        Section(title: "Kinds of calls", items: [
            Item(symbol: .kind(.turn), title: "Turn", detail: "The whole question. Everything else nests under it."),
            Item(symbol: .kind(.function), title: "Function", detail: "A traced step such as routeDomain, routeSkill, fillSlots, or fulfill. In Tree and Timeline, a function with one same-name model child folds into a single row; open the row for the model transcript."),
            Item(symbol: .kind(.model), title: "Foundation Models call", detail: "One on-device model request. Tap it for the instructions, the prompt, tool calls, the response, and context-window use. A same-name child of a function is shown on the function row instead of as its own Tree line. A specialist uses its own symbol there. Other model calls keep the brain."),
            Item(symbol: .kind(.tool), title: "Tool call", detail: "A tool wrapped with AskTrace.tool. Tool calls the model made also appear inside the model transcript."),
            Item(symbol: .kind(.userWait), title: "Waiting", detail: "Time a host wrapped in userWait, such as a follow-up prompt. Not app work.")
        ]),
        Section(title: "Markers", items: [
            Item(symbol: .glyph("→"), title: "Result", detail: "A short summary of what the step returned, such as the domain id."),
            Item(symbol: .system("arrow.triangle.branch", .purple), title: "Decision", detail: "Why the turn took a branch. Router skipped means the skill was chosen without a router model. A specialist can still call the model after that. Joined onto the previous question means a follow-up was sent with the question before it. A generated card says the layout came from the skill, the model composed it, or the fact layout was used."),
            Item(symbol: .glyph("∥"), title: "Ran in parallel", detail: "This call overlapped another call under the same parent."),
            Item(symbol: .system("xmark.octagon", .red), title: "Threw an error", detail: "The call ended by throwing."),
            Item(symbol: .system("hourglass", .secondary), title: "Unfinished", detail: "Still running when the turn ended. Its end is clamped to the turn's end.")
        ]),
        Section(title: "How time is measured", items: [
            Item(symbol: .system("stopwatch", .accent), title: "Durations are wall time", detail: "From entering a call to leaving it, children and waiting included. It is not CPU time."),
            Item(symbol: .system("clock", .accent), title: "One clock per turn", detail: "Start times are seconds since the question was asked, on a monotonic clock."),
            Item(symbol: .system("chart.bar.xaxis", .accent), title: "Timeline", detail: "Each bar starts when the call started. Compress waits removes userWait time from the axis.")
        ]),
        Section(title: "Context window", items: [
            Item(symbol: .contextBadge(sample(1_264)), title: "Share of the window used", detail: "Tokens the session held after the call, from Response.usage on iOS 27."),
            Item(symbol: .contextBadge(sample(3_200)), title: "75% or more", detail: "Close to the limit."),
            Item(symbol: .contextBadge(sample(3_800)), title: "90% or overflowed", detail: "At the limit. An overflow fails the call and records the error's own counts.")
        ]),
        Section(
            title: "Keeping and sharing",
            items: [
                Item(symbol: .system("point.3.connected.trianglepath.dotted", .accent), title: "Chat button", detail: "The trace button in the chat header. A host window can also call AskTraceViewer.present."),
                Item(symbol: .system("internaldrive", .secondary), title: "Last 20 turns", detail: "Saved as soon as the turn ends. Pass an app group to AskTraceStore.live when a widget or Siri process should share the files."),
                Item(symbol: .system("square.and.arrow.up", .accent), title: "Share", detail: "Shares a picture of the question, the answer, and the cards, plus the indented text and a JSON file."),
                Item(symbol: .system("square.and.arrow.down", .accent), title: "Drop a trace", detail: "Drop a trace JSON onto the list. It opens under Viewing and is not saved with the last 20. Swipe the row to remove it.")
            ],
            footer: "Debug builds only. Traces include prompts and tool output. Release builds do not write them."
        )
    ]

    private static func sample(_ used: Int) -> AskTraceContextUsage {
        AskTraceContextUsage(source: .responseUsage, contextSize: 4_096, usedTokens: used)
    }
}
#endif
