import Foundation
import os
import Testing
@testable import AskKit

@Suite("Generated card sources")
struct AskGeneratedCardSourceTests {
    @Test func olderCardJSONDecodesWithoutSources() throws {
        let json = """
        {"kind":"vstack","text":"","detail":"","actionID":"","children":[{"kind":"stat","text":"72°","detail":"","actionID":"","children":[]}]}
        """
        let decoded = try #require(AskGeneratedCard.decode(json))
        #expect(decoded.sources.isEmpty)
        #expect(decoded.children[0].sources.isEmpty)
        #expect(decoded.children[0].text == "72°")
        let again = AskGeneratedCard.encode(decoded)
        #expect(!again.contains("\"sources\""))
    }

    @Test func sourcesRoundTripThroughJSON() throws {
        let root = AskCardNode(
            kind: "vstack",
            children: [AskCardNode(kind: "stat", text: "72°")],
            sources: [AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today"))]
        )
        let decoded = try #require(AskGeneratedCard.decode(AskGeneratedCard.encode(root)))
        #expect(decoded.sources.map(\.name) == ["Weather"])
        #expect(decoded.sources.first?.url?.absoluteString == "https://weather.example/today")
        #expect(decoded == root)
    }

    @Test func aRejectedURLDoesNotStayInTheIdentifier() throws {
        let json = #"{"name":"Weather","url":"javascript:alert(1)","id":"weather|javascript:alert(1)"}"#
        let source = try JSONDecoder().decode(AskCardSource.self, from: Data(json.utf8))
        #expect(source.name == "Weather")
        #expect(source.url == nil)
        #expect(source.id == "weather")

        let file = try JSONDecoder().decode(
            AskCardSource.self,
            from: Data(#"{"name":"Files","url":"file:///tmp/secret"}"#.utf8)
        )
        #expect(file.url == nil)
    }

    @Test func theSanitizerDropsBlankRejectedAndDuplicateSourcesAndKeepsFour() throws {
        var hostile = AskCardSource(name: "Weather", id: "weather|javascript:alert(1)")
        hostile.url = URL(string: "javascript:alert(1)")
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "stat", text: "8,420"),
                AskCardNode(
                    kind: "text",
                    text: "Today",
                    sources: [AskCardSource(name: "Health", id: "from-the-child")]
                )
            ],
            sources: [
                AskCardSource(name: "  "),
                hostile,
                AskCardSource(name: "Calendar", id: "cal"),
                AskCardSource(name: "Calendar", id: "cal"),
                AskCardSource(name: "Health", url: URL(string: "https://health.example/steps")),
                AskCardSource(name: "Music"),
                AskCardSource(name: "Notes"),
                AskCardSource(name: "Extra")
            ]
        )
        let sanitized = try #require(AskGeneratedCard.sanitize(root))
        #expect(sanitized.sources.map(\.name) == ["Weather", "Calendar", "Health", "Music"])
        #expect(sanitized.sources[0].url == nil)
        #expect(sanitized.sources[1].id == "cal")
        #expect(sanitized.sources[2].url?.scheme == "https")
        #expect(sanitized.children[1].sources.map(\.id) == ["from-the-child"])
        let shown = AskGeneratedCard.sources(in: sanitized)
        #expect(shown.map(\.name) == ["Weather", "Calendar", "Health", "Music", "Health"])
        #expect(AskGeneratedCard.sourceLine(shown, includingLinks: false) == "Source: Weather, Calendar, Health, Music, Health")
        #expect(AskGeneratedCard.sourceLine([sanitized.sources[2]]).contains("https://health.example/steps"))
    }

    @Test @MainActor func blueprintSourcesAttachToTheCardAndTheShareLine() throws {
        let card = AskGeneratedCard.card(
            title: "Forecast",
            spoken: "It is 72 degrees.",
            facts: "72°",
            root: AskGeneratedCard.factTree(title: "Weather", value: "72°", detail: "Partly cloudy"),
            sources: [
                AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today")),
                AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today"))
            ]
        )
        let root = try #require(card.generatedRoot)
        #expect(root.sources.map(\.name) == ["Weather"])
        #expect(card.shareText.contains("Source: Weather (https://weather.example/today)"))
        #expect(AskGeneratedCard.outline(root).contains("source · Weather"))
        let restored = try #require(AskGeneratedCard.decode(AskGeneratedCard.encode(root)))
        #expect(restored.sources.map(\.name) == ["Weather"])
    }
}

@MainActor
@Suite("Composition progress")
struct AskCompositionProgressTests {
    @Test func phasesMoveForwardAndRecordDurationsInOrder() {
        var state = AskCompositionState()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        state.start(now: start)
        state.note(chat: .tool, now: start.addingTimeInterval(0.4))
        state.note(chat: .writing, now: start.addingTimeInterval(1.0))
        state.advance(to: .composing, now: start.addingTimeInterval(1.4))
        state.finish(now: start.addingTimeInterval(2.0))

        #expect(state.snapshot.records.map(\.phase) == [.understanding, .lookingUp, .preparing, .composing])
        #expect(state.snapshot.steps.map(\.state) == [.finished, .finished, .finished, .finished])
        #expect(close(state.snapshot.records[0].duration, 0.4))
        #expect(close(state.snapshot.records[1].duration, 0.6))
        #expect(close(state.snapshot.records[2].duration, 0.4))
        #expect(close(state.snapshot.records[3].duration, 0.6))
        #expect(state.snapshot.steps.map(\.timingLabel) == ["0.4s", "0.6s", "0.4s", "0.6s"])
        #expect(state.snapshot.isRunning == false)
    }

    @Test func aLaterPhaseDoesNotReopenAnEarlierOne() {
        var state = AskCompositionState()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        state.start(now: start)
        state.advance(to: .composing, now: start.addingTimeInterval(1))
        let ignored = state.note(chat: .tool, now: start.addingTimeInterval(2))

        #expect(ignored.isEmpty)
        #expect(state.snapshot.step(.composing)?.state == .active)
        #expect(state.snapshot.step(.lookingUp)?.state == .skipped)
        #expect(state.snapshot.step(.preparing)?.state == .skipped)
        #expect(state.snapshot.records.map(\.phase) == [.understanding])
        state.finish(now: start.addingTimeInterval(2))
        #expect(state.snapshot.records.map(\.phase) == [.understanding, .composing])
    }

    @Test func thinkingStaysOnUnderstandAndAToolCallIsSearch() {
        var state = AskCompositionState()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        state.start(now: start)
        #expect(state.note(chat: .thinking, now: start.addingTimeInterval(0.2)).isEmpty)
        #expect(state.note(chat: .choosing, now: start.addingTimeInterval(0.2)).isEmpty)
        #expect(state.snapshot.step(.understanding)?.state == .active)
        state.note(chat: .tool, now: start.addingTimeInterval(0.5))
        #expect(state.snapshot.step(.lookingUp)?.state == .active)
        #expect(state.snapshot.records.map(\.phase) == [.understanding])
    }

    @Test func timingLabelsStayShort() {
        #expect(AskCompositionTiming.label(seconds: 0.01) == "<0.1s")
        #expect(AskCompositionTiming.label(seconds: 0.4) == "0.4s")
        #expect(AskCompositionTiming.label(seconds: 12) == "12s")
        #expect(AskCompositionTiming.spoken(seconds: 1) == "1 second")
        #expect(AskCompositionTiming.spoken(seconds: 2) == "2 seconds")
    }

    @Test func theStreamYieldsTheChecklistInOrder() async {
        let progress = AskCompositionProgress()
        let stream = progress.updates()
        var iterator = stream.makeAsyncIterator()
        let waiting = await iterator.next()
        #expect(waiting?.isRunning == false)

        let start = Date(timeIntervalSinceReferenceDate: 0)
        progress.begin(now: start)
        let understanding = await iterator.next()
        #expect(understanding?.step(.understanding)?.state == .active)

        progress.advance(to: .lookingUp, now: start.addingTimeInterval(0.25))
        let searching = await iterator.next()
        #expect(searching?.step(.lookingUp)?.state == .active)
        #expect(searching?.records.map(\.phase) == [.understanding])

        progress.advance(to: .preparing, now: start.addingTimeInterval(0.5))
        let preparing = await iterator.next()
        #expect(preparing?.step(.preparing)?.state == .active)

        progress.advance(to: .composing, now: start.addingTimeInterval(0.75))
        let composing = await iterator.next()
        #expect(composing?.step(.composing)?.state == .active)

        progress.finish(now: start.addingTimeInterval(1))
        let done = await iterator.next()
        #expect(done?.isRunning == false)
        #expect(done?.records.map(\.phase) == [.understanding, .lookingUp, .preparing, .composing])
        #expect(progress.records.map(\.phase) == [.understanding, .lookingUp, .preparing, .composing])
    }

    @Test func theMetricsLogAppendsFinishedPhasesInOrder() {
        let marker = "composition-metrics-\(UUID().uuidString)"
        let seen = OSAllocatedUnfairLock(initialState: [String]())
        let previous = AskCompositionMetrics.onRecord
        AskCompositionMetrics.onRecord = { @Sendable record in
            guard record.duration == 1.25 || record.duration == 2.5 else { return }
            seen.withLock { $0.append("\(marker):\(record.phase.rawValue)") }
        }
        defer { AskCompositionMetrics.onRecord = previous }

        let progress = AskCompositionProgress()
        progress.recordsMetrics = true
        let start = Date(timeIntervalSinceReferenceDate: 0)
        progress.begin(now: start)
        progress.advance(to: .composing, now: start.addingTimeInterval(1.25))
        progress.finish(now: start.addingTimeInterval(3.75))

        let lines = seen.withLock { $0 }
        #expect(lines == ["\(marker):understanding", "\(marker):composing"])
        #expect(AskCompositionMetrics.records().contains { $0.phase == .understanding && $0.duration == 1.25 })
        #expect(AskCompositionMetrics.records().contains { $0.phase == .composing && $0.duration == 2.5 })
    }

    private func close(_ value: TimeInterval, _ expected: TimeInterval) -> Bool {
        abs(value - expected) < 0.000_001
    }
}
