import Foundation
import os
import XCTest
@testable import AskKit

#if DEBUG
final class AskTraceTests: XCTestCase {
    private struct Boom: Error {}

    private var finished: OSAllocatedUnfairLock<[AskTraceTurn]>!
    private var recorder: AskTraceRecorder!

    override func setUp() {
        super.setUp()
        let finished = OSAllocatedUnfairLock(initialState: [AskTraceTurn]())
        self.finished = finished
        recorder = AskTraceRecorder { turn in
            finished.withLock { $0.append(turn) }
        }
    }

    func testNestedSpansShareParents() async {
        let turn = await record {
            await AskTrace.turn("is it ready", entry: .composer) {
                AskTrace.span("outer") {
                    AskTrace.span("inner") {}
                }
            }
        }
        let root = turn?.spans.first
        let outer = span(named: "outer", in: turn)
        let inner = span(named: "inner", in: turn)
        XCTAssertEqual(turn?.question, "is it ready")
        XCTAssertEqual(turn?.entry, .composer)
        XCTAssertEqual(root?.kind, .turn)
        XCTAssertNil(root?.parentID)
        XCTAssertEqual(outer?.parentID, root?.id)
        XCTAssertEqual(inner?.parentID, outer?.id)
        XCTAssertNotNil(turn?.duration)
    }

    func testTurnInsideATurnBecomesASpan() async {
        let turn = await record {
            await AskTrace.turn("outer", entry: .composer) {
                await AskTrace.turn("inner", entry: .chip) {}
            }
        }
        XCTAssertEqual(finished.withLock { $0.count }, 1)
        XCTAssertNotNil(span(named: "turn (chip)", in: turn))
        XCTAssertEqual(span(named: "turn (chip)", in: turn)?.parentID, turn?.spans.first?.id)
    }

    func testAsyncLetChildrenShareAParent() async {
        let turn = await record {
            await AskTrace.turn("q", entry: .composer) {
                async let first: Void = AskTrace.span("followUp") {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
                await AskTrace.span("compose") {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
                await first
            }
        }
        let root = turn?.spans.first?.id
        let followUp = span(named: "followUp", in: turn)
        let compose = span(named: "compose", in: turn)
        XCTAssertEqual(followUp?.parentID, root)
        XCTAssertEqual(compose?.parentID, root)
        XCTAssertTrue(AskTraceViewModel.overlapsSibling(followUp!, siblings: [followUp!, compose!]))
    }

    func testThrowClosesTheSpanAndTheTurn() async {
        let turn = await record {
            do {
                try await AskTrace.turn("q", entry: .composer) {
                    try AskTrace.span("boom") { throw Boom() }
                }
            } catch {}
        }
        guard case .threw = span(named: "boom", in: turn)?.status else {
            return XCTFail("Expected the span to record the throw")
        }
        XCTAssertNotNil(turn?.duration)
    }

    func testUnfinishedChildIsClampedToTheTurn() {
        let context = recorder.beginTurn(question: "q", entry: .composer, function: "test", fileID: "test", line: 1)
        _ = recorder.openSpan(
            parent: context,
            name: "orphan",
            kind: .function,
            attributes: [],
            function: "test",
            fileID: "test",
            line: 1
        )
        recorder.endTurn(context.turnID)
        let turn = finished.withLock { $0.last }
        XCTAssertEqual(span(named: "orphan", in: turn)?.status, .unfinished)
        XCTAssertNotNil(span(named: "orphan", in: turn)?.end)
    }

    func testSpanOutsideATurnRunsAndRecordsNothing() async {
        var ran = false
        _ = await record {
            AskTrace.span("nope") { ran = true }
        }
        XCTAssertTrue(ran)
        XCTAssertTrue(finished.withLock { $0.isEmpty })
    }

    func testToolSpanFallsBackToTheOpenModelSpan() async {
        // `Task.detached` does not inherit task-locals. Production shares `AskTraceRecorder.live`; the test
        // rebinds the same recorder so the tool can still find the open model span.
        let bound: AskTraceRecorder = recorder
        let turn = await record {
            await AskTrace.turn("q", entry: .composer) {
                await AskTrace.span("model", kind: .model) {
                    await Task.detached {
                        await AskTrace.$recorder.withValue(bound) {
                            _ = try? await AskTrace.tool("lookup", arguments: "city=Austin") { "ok" }
                        }
                    }.value
                }
            }
        }
        let model = span(named: "model", in: turn)
        let toolSpan = span(named: "tool lookup", in: turn)
        XCTAssertEqual(toolSpan?.kind, .tool)
        XCTAssertEqual(toolSpan?.parentID, model?.id)
        XCTAssertEqual(toolSpan?.result, "ok")
    }

    func testStoreKeepsTheNewestLimitAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AskKitTraces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskTraceStore.live(directory: directory, limit: 2)
        let first = sampleTurn(question: "one", at: 1)
        let second = sampleTurn(question: "two", at: 2)
        let third = sampleTurn(question: "three", at: 3)
        store.save(first)
        store.save(second)
        store.save(third)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.map(\.question).sorted(), ["three", "two"])
        store.delete(third.id)
        XCTAssertEqual(store.loadAll().map(\.question), ["two"])
        store.clear()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testLookupPicksTheTraceClosestToTheAnswer() {
        let older = sampleTurn(question: "What are the hours", at: 10)
        let newer = sampleTurn(question: "What are the hours", at: 80)
        let other = sampleTurn(question: "Where is parking", at: 80)
        let when = Date(timeIntervalSince1970: 1_700_000_000 + 90)
        let id = AskTraceStore.match(question: "  What are the hours ", near: when, turns: [older, other, newer])
        XCTAssertEqual(id, newer.id)
        XCTAssertNil(AskTraceStore.match(question: "   ", near: when, turns: [newer]))
        XCTAssertNil(AskTraceStore.match(question: "missing", near: when, turns: [newer]))
    }

    func testTimelineCompressesUserWaitsAndSummaryCountsTheRoute() {
        let root = UUID()
        let wait = UUID()
        let work = UUID()
        let turn = AskTraceTurn(
            id: UUID(),
            question: "q",
            entry: .composer,
            startedAt: Date(),
            duration: 10,
            spans: [
                sampleSpan(id: root, parent: nil, name: "turn", kind: .turn, start: 0, end: 10, attributes: [
                    .init(key: "routedVia", value: "model"),
                    .init(key: "routedVia", value: "fallback")
                ]),
                sampleSpan(id: wait, parent: root, name: "wait", kind: .userWait, start: 2, end: 7),
                sampleSpan(id: work, parent: root, name: "work", kind: .function, start: 7, end: 10)
            ]
        )
        let bars = AskTraceViewModel.timelineBars(turn: turn, compressWaits: true)
        let waitBar = bars.first { $0.span.kind == .userWait }
        let workBar = bars.first { $0.span.name == "work" }
        XCTAssertEqual(waitBar?.width ?? 1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(workBar?.width ?? 0, 0.4)
        let summary = AskTraceViewModel.summary(turn: turn)
        XCTAssertEqual(summary.routedVia, "fallback")
        XCTAssertEqual(summary.userWait, 5, accuracy: 0.001)
        let tree = AskTraceViewModel.buildTree(spans: turn.spans)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].children.count, 2)
    }

    func testStoryShowsTheSnippetCards() {
        let bodies = AskTracePoster.encodeBodies([
            "Flight status\nDoors close at noon.",
            "Steps\n8421 steps"
        ])
        let turn = posterTurn(question: "status", attributes: [
            .init(key: "shownAnswer", value: "Doors close at noon."),
            .init(key: "shownCards", value: "Flight status, Steps"),
            .init(key: "shownCardBodies", value: try! XCTUnwrap(bodies))
        ])
        let story = AskTraceFormatter.story(for: turn)
        let snippet = story.first { $0.title == "Snippet" }
        XCTAssertEqual(snippet?.cards, [
            AskTracePosterCard(title: "Flight status", body: "Doors close at noon."),
            AskTracePosterCard(title: "Steps", body: "8421 steps")
        ])
        XCTAssertNil(story.first { $0.title == "They saw" })
        let heard = story.firstIndex { $0.title == "They heard" }
        let shown = story.firstIndex { $0.title == "Snippet" }
        XCTAssertEqual(shown, heard.map { $0 + 1 })
    }

    func testAssistantTurnMatchesTheQuestionClosestToTheTrace() {
        let earlier = AskTranscriptTurn(
            id: UUID(), role: "user", text: "Where is Apple Park", spoken: "",
            skillID: "", domainID: "", slotsJSON: "{}", createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let first = AskTranscriptTurn(
            id: UUID(), role: "assistant", text: "Apple Park.", spoken: "Apple Park.",
            skillID: "answer", domainID: "open", slotsJSON: "{}", createdAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        let again = AskTranscriptTurn(
            id: UUID(), role: "user", text: "Where is Apple Park", spoken: "",
            skillID: "", domainID: "", slotsJSON: "{}", createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let second = AskTranscriptTurn(
            id: UUID(), role: "assistant", text: "Still Apple Park.", spoken: "Still Apple Park.",
            skillID: "answer", domainID: "open", slotsJSON: "{}", createdAt: Date(timeIntervalSince1970: 1_700_000_108)
        )
        let turns = [earlier, first, again, second]
        XCTAssertEqual(
            AskTraceStore.assistantTurn(matching: " Where is Apple Park ", near: Date(timeIntervalSince1970: 1_700_000_100), turns: turns),
            second.id
        )
        XCTAssertNil(AskTraceStore.assistantTurn(matching: "   ", near: Date(), turns: turns))
        XCTAssertNil(AskTraceStore.assistantTurn(matching: "missing", near: Date(), turns: turns))
    }

    func testStorySaysWhenTheSnippetHadNoCard() {
        let story = AskTraceFormatter.story(for: sampleTurn(question: "hello", at: 0))
        let snippet = story.first { $0.title == "Snippet" }
        XCTAssertEqual(snippet?.text, "No snippet card.")
        XCTAssertEqual(snippet?.cards, [])
        XCTAssertEqual(story.first { $0.title == "Model calls" }?.text, "No model call.")
    }

    func testStoryNamesTheModelWhenTheRouterWasSkipped() {
        let root = UUID()
        let follow = UUID()
        let model = UUID()
        let prompt = """
        QUESTION
        What's been my heart rate for the past week
        What about my calories burned

        SKILL
        answer
        """
        let turn = AskTraceTurn(
            id: UUID(),
            question: "What about my calories burned",
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 4,
            spans: [
                AskTraceSpan(
                    id: root,
                    parentID: nil,
                    name: "Ask turn",
                    kind: .turn,
                    function: "test",
                    fileID: "test",
                    line: 1,
                    start: 0,
                    end: 4,
                    status: .ok,
                    attributes: [
                        .init(key: "routedVia", value: "fastPath"),
                        .init(key: "skill", value: "answer")
                    ],
                    result: nil,
                    events: [.init(offset: 0, kind: .decision, message: "fast path")],
                    model: nil
                ),
                AskTraceSpan(
                    id: follow,
                    parentID: root,
                    name: "followUp",
                    kind: .function,
                    function: "test",
                    fileID: "test",
                    line: 1,
                    start: 0,
                    end: 0.1,
                    status: .ok,
                    attributes: [],
                    result: nil,
                    events: [.init(offset: 0, kind: .decision, message: "joined to the previous question")],
                    model: nil
                ),
                AskTraceSpan(
                    id: model,
                    parentID: root,
                    name: "specialist health",
                    kind: .model,
                    function: "test",
                    fileID: "test",
                    line: 1,
                    start: 0.1,
                    end: 4,
                    status: .ok,
                    attributes: [],
                    result: nil,
                    events: [],
                    model: AskTraceModelCall(
                        label: "specialist health",
                        prewarmed: nil,
                        items: [.init(kind: .prompt, toolName: nil, text: prompt)],
                        output: nil,
                        errorKind: nil,
                        errorDescription: nil,
                        context: nil
                    )
                )
            ]
        )
        let story = AskTraceFormatter.story(for: turn)
        XCTAssertEqual(
            story.first { $0.title == "Routed via" }?.text,
            "Router skipped. The skill was chosen without a router model."
        )
        XCTAssertEqual(story.first { $0.title == "Model calls" }?.text, "specialist health")
        XCTAssertEqual(
            story.first { $0.title == "Sent to the model" }?.text,
            "What's been my heart rate for the past week\nWhat about my calories burned"
        )
        XCTAssertEqual(story.first { $0.title == "Why this path" }?.text, "Joined onto the previous question")
        XCTAssertFalse(story.contains { $0.text == "fast path" })
        XCTAssertEqual(AskTraceFormatter.routeWords("fastPath"), "Router skipped")
        XCTAssertEqual(AskTraceFormatter.decisionWords("fast path"), "Router skipped")
    }

    func testStoryUsesTheRecordedPromptQuestion() {
        let same = posterTurn(question: "Steps today", attributes: [
            .init(key: "promptQuestion", value: "Steps today")
        ])
        XCTAssertNil(AskTraceFormatter.story(for: same).first { $0.title == "Sent to the model" })

        let joined = posterTurn(question: "What about my calories burned", attributes: [
            .init(key: "promptQuestion", value: "Heart rate this week\nWhat about my calories burned")
        ])
        XCTAssertEqual(
            AskTraceFormatter.story(for: joined).first { $0.title == "Sent to the model" }?.text,
            "Heart rate this week\nWhat about my calories burned"
        )
    }

    func testPosterUsesTheRecordedAnswerAndCardWords() {
        let bodies = AskTracePoster.encodeBodies([
            "Flight status\nDoors close at noon.",
            "Steps"
        ])
        let turn = posterTurn(
            question: "What's my flight status?",
            attributes: [
                .init(key: "shownAnswer", value: "Doors close at noon."),
                .init(key: "shownCards", value: "Flight status, Steps"),
                .init(key: "shownCardBodies", value: try! XCTUnwrap(bodies))
            ]
        )
        let content = AskTracePoster.content(for: turn)
        XCTAssertEqual(content.question, "What's my flight status?")
        XCTAssertEqual(content.answer, "Doors close at noon.")
        XCTAssertEqual(content.cards, [
            AskTracePosterCard(title: "Flight status", body: "Doors close at noon."),
            AskTracePosterCard(title: "Steps", body: "")
        ])
    }

    func testPosterMatchesAToolAndZipsTheRest() {
        let root = UUID()
        let battery = UUID()
        let health = UUID()
        let turn = AskTraceTurn(
            id: UUID(),
            question: "battery and steps",
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1,
            spans: [
                sampleSpan(id: root, parent: nil, name: "turn", kind: .turn, start: 0, end: 1, attributes: [
                    .init(key: "shownAnswer", value: "80 percent."),
                    .init(key: "shownCards", value: "Battery, Steps")
                ]),
                sampleSpan(id: battery, parent: root, name: "tool battery", kind: .tool, start: 0, end: 1, result: "80 percent"),
                sampleSpan(id: health, parent: root, name: "tool health", kind: .tool, start: 0, end: 1, result: "8421 steps")
            ]
        )
        XCTAssertEqual(AskTracePoster.content(for: turn).cards, [
            AskTracePosterCard(title: "Battery", body: "80 percent"),
            AskTracePosterCard(title: "Steps", body: "8421 steps")
        ])
    }

    func testPosterKeepsAnUnmatchedToolWhenTheCountsDiffer() {
        let root = UUID()
        let health = UUID()
        let turn = AskTraceTurn(
            id: UUID(),
            question: "steps and heart",
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1,
            spans: [
                sampleSpan(id: root, parent: nil, name: "turn", kind: .turn, start: 0, end: 1, attributes: [
                    .init(key: "shownCards", value: "Steps, Heart rate")
                ]),
                sampleSpan(id: health, parent: root, name: "tool health", kind: .tool, start: 0, end: 1, result: "72 bpm")
            ]
        )
        let content = AskTracePoster.content(for: turn)
        XCTAssertEqual(content.answer, "It was not recorded.")
        XCTAssertEqual(content.cards.map(\.title), ["Steps", "Heart rate", "health"])
        XCTAssertEqual(content.cards[2].body, "72 bpm")
    }

    func testPosterUsesTheToolWhenTheCardBodyIsTheSpeech() {
        let speech = "You are currently listening to \"Fight For Snake Mountain\" by Daniel Pemberton."
        let song = "Song: Fight For Snake Mountain · Daniel Pemberton · Masters of the Universe (Original Motion Picture Soundtrack) · 3:55"
        let bodies = AskTracePoster.encodeBodies([speech])
        let root = UUID()
        let music = UUID()
        let turn = AskTraceTurn(
            id: UUID(),
            question: "What's my last played song?",
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1,
            spans: [
                sampleSpan(id: root, parent: nil, name: "turn", kind: .turn, start: 0, end: 1, attributes: [
                    .init(key: "shownAnswer", value: speech),
                    .init(key: "shownCards", value: "Fight For Snake Mountain"),
                    .init(key: "shownCardBodies", value: try! XCTUnwrap(bodies))
                ]),
                sampleSpan(id: music, parent: root, name: "tool music", kind: .tool, start: 0, end: 1, result: song)
            ]
        )
        XCTAssertEqual(AskTracePoster.content(for: turn).cards, [
            AskTracePosterCard(
                title: "Fight For Snake Mountain",
                body: "Daniel Pemberton\nMasters of the Universe (Original Motion Picture Soundtrack)\n3:55"
            )
        ])
    }

    func testPosterClipsALongCardBody() {
        let long = String(repeating: "a", count: AskTracePoster.bodyLimit + 40)
        let bodies = AskTracePoster.encodeBodies([long])
        let turn = posterTurn(question: "q", attributes: [
            .init(key: "shownCards", value: "Notes"),
            .init(key: "shownCardBodies", value: try! XCTUnwrap(bodies))
        ])
        let body = AskTracePoster.content(for: turn).cards[0].body
        XCTAssertEqual(body.count, AskTracePoster.bodyLimit + 1)
        XCTAssertTrue(body.hasSuffix("…"))
    }

    func testImportReadsTheShareFileAndTheStoreFile() throws {
        let turn = sampleTurn(question: "hours", at: 0)
        let share = JSONEncoder()
        share.dateEncodingStrategy = .iso8601
        share.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stored = JSONEncoder()
        XCTAssertEqual(try AskTraceImport.turns(in: share.encode(turn)), [turn])
        XCTAssertEqual(try AskTraceImport.turns(in: stored.encode(turn)), [turn])
        XCTAssertEqual(try AskTraceImport.turns(in: share.encode([turn])), [turn])
        XCTAssertTrue(AskTraceImport.turns(in: Data("nope".utf8)).isEmpty)
        XCTAssertTrue(AskTraceImport.turns(in: Data("[]".utf8)).isEmpty)
    }

    func testADroppedTraceIsOnlyViewed() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AskKitTraces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskTraceStore.live(directory: directory, limit: 20)
        let saved = sampleTurn(question: "saved", at: 1)
        store.save(saved)
        let dropped = sampleTurn(question: "dropped", at: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(dropped)
        let savedData = try! encoder.encode(saved)
        await MainActor.run {
            let model = AskTraceViewModel(store: store)
            model.onAppear()
            XCTAssertEqual(model.turns.map(\.id), [saved.id])
            XCTAssertTrue(model.onImport(data))
            XCTAssertEqual(model.viewing.map(\.question), ["dropped"])
            XCTAssertTrue(model.onImport(data))
            XCTAssertEqual(model.viewing.count, 1)
            XCTAssertTrue(model.onImport(savedData))
            XCTAssertEqual(model.viewing.count, 1)
            XCTAssertFalse(model.onImport(Data("nope".utf8)))
            model.onClearTapped()
            XCTAssertTrue(model.turns.isEmpty)
            XCTAssertEqual(model.viewing.map(\.id), [dropped.id])
            model.onDismissViewing(dropped.id)
            XCTAssertTrue(model.viewing.isEmpty)
            XCTAssertEqual(model.turn(dropped.id)?.question, nil)
        }
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testWorkedCaptionUsesCompactDurationAndToolSteps() {
        XCTAssertEqual(AskTraceFormatter.workedDuration(0.4), "<1s")
        XCTAssertEqual(AskTraceFormatter.workedDuration(8), "8s")
        XCTAssertEqual(AskTraceFormatter.workedDuration(131), "2m 11s")
        XCTAssertEqual(AskTraceFormatter.workedSteps(toolCalls: 1, modelCalls: 2), 1)
        XCTAssertEqual(AskTraceFormatter.workedSteps(toolCalls: 0, modelCalls: 2), 2)
        XCTAssertEqual(
            AskTraceFormatter.workedCaption(duration: 8, toolCalls: 1, modelCalls: 2),
            "Worked 8s · 1 step"
        )
        XCTAssertEqual(
            AskTraceFormatter.workedCaption(duration: 131, toolCalls: 0, modelCalls: 2),
            "Worked 2m 11s · 2 steps"
        )
        XCTAssertEqual(AskTraceFormatter.workedSymbol(toolCalls: 1), "wrench.and.screwdriver")
        XCTAssertEqual(AskTraceFormatter.workedSymbol(toolCalls: 0), "doc.text")
    }

    func testASpecialistSymbolReplacesTheModelBrain() {
        let photos = AskTraceSpan.Attribute(key: "symbol", value: "photo.on.rectangle")
        let blank = AskTraceSpan.Attribute(key: "symbol", value: "  ")
        let specialist = sampleSpan(
            id: UUID(),
            parent: nil,
            name: "specialist open.photos",
            kind: .function,
            start: 0,
            end: 1,
            attributes: [photos]
        )
        let model = sampleSpan(
            id: UUID(),
            parent: specialist.id,
            name: "specialist open.photos",
            kind: .model,
            start: 0,
            end: 1,
            attributes: [photos]
        )
        let writer = sampleSpan(id: UUID(), parent: nil, name: "writer", kind: .function, start: 0, end: 1)
        let writerModel = sampleSpan(id: UUID(), parent: writer.id, name: "writer", kind: .model, start: 0, end: 1)
        let empty = sampleSpan(
            id: UUID(),
            parent: nil,
            name: "specialist app.recipes",
            kind: .function,
            start: 0,
            end: 1,
            attributes: [blank]
        )
        XCTAssertEqual(AskTraceFormatter.inlinedSymbol(span: specialist, model: model), "photo.on.rectangle")
        XCTAssertEqual(AskTraceFormatter.rowSymbol(specialist), "photo.on.rectangle")
        XCTAssertEqual(AskTraceFormatter.inlinedSymbol(span: writer, model: writerModel), "brain")
        XCTAssertEqual(AskTraceFormatter.rowSymbol(writer), "function")
        XCTAssertEqual(AskTraceFormatter.inlinedSymbol(span: empty, model: model), "photo.on.rectangle")
        XCTAssertEqual(AskTraceFormatter.rowSymbol(empty), "function")
        XCTAssertEqual(AskTraceFormatter.kindSymbol(.model), "brain")
    }

    func testVisibleRowsCollapseSameNameFunctionAndModel() {
        let root = UUID()
        let writer = UUID()
        let writerModel = UUID()
        let spans = [
            sampleSpan(id: root, parent: nil, name: "Ask turn", kind: .turn, start: 0, end: 4),
            sampleSpan(id: writer, parent: root, name: "writer", kind: .function, start: 1, end: 4, result: "68 percent"),
            sampleSpan(id: writerModel, parent: writer, name: "writer", kind: .model, start: 1.1, end: 3.9)
        ]
        let tree = AskTraceViewModel.buildTree(spans: spans)
        let rows = AskTraceViewModel.visibleRows(tree: tree, expanded: Set(spans.map(\.id)))
        XCTAssertEqual(rows.map(\.span.id), [root, writer])
        XCTAssertEqual(rows[1].inlinedModel?.id, writerModel)
        XCTAssertFalse(rows.contains { $0.span.id == writerModel })
    }

    func testVisibleRowsPromoteToolsUnderCollapsedModel() {
        let root = UUID()
        let specialist = UUID()
        let model = UUID()
        let tool = UUID()
        let spans = [
            sampleSpan(id: root, parent: nil, name: "Ask turn", kind: .turn, start: 0, end: 5),
            sampleSpan(id: specialist, parent: root, name: "specialist location", kind: .function, start: 1, end: 5),
            sampleSpan(id: model, parent: specialist, name: "specialist location", kind: .model, start: 1.1, end: 4.8),
            sampleSpan(id: tool, parent: model, name: "tool location", kind: .tool, start: 2, end: 3)
        ]
        let tree = AskTraceViewModel.buildTree(spans: spans)
        let rows = AskTraceViewModel.visibleRows(tree: tree, expanded: Set(spans.map(\.id)))
        XCTAssertEqual(rows.map(\.span.name), ["Ask turn", "specialist location", "tool location"])
        XCTAssertEqual(rows[1].inlinedModel?.id, model)
        XCTAssertEqual(rows[2].depth, 2)
        XCTAssertEqual(rows[2].span.id, tool)
    }

    func testVisibleRowsKeepDistinctModelNamesSeparate() {
        let root = UUID()
        let route = UUID()
        let model = UUID()
        let spans = [
            sampleSpan(id: root, parent: nil, name: "Ask turn", kind: .turn, start: 0, end: 3),
            sampleSpan(id: route, parent: root, name: "route", kind: .function, start: 1, end: 3),
            sampleSpan(id: model, parent: route, name: "respond", kind: .model, start: 1.1, end: 2.9)
        ]
        let tree = AskTraceViewModel.buildTree(spans: spans)
        let rows = AskTraceViewModel.visibleRows(tree: tree, expanded: Set(spans.map(\.id)))
        XCTAssertEqual(rows.map(\.span.id), [root, route, model])
        XCTAssertNil(rows[1].inlinedModel)
    }

    private func record(_ body: () async throws -> Void) async rethrows -> AskTraceTurn? {
        try await AskTrace.$recorder.withValue(recorder) {
            try await body()
        }
        return finished.withLock { $0.last }
    }

    private func span(named name: String, in turn: AskTraceTurn?) -> AskTraceSpan? {
        turn?.spans.first { $0.name == name }
    }

    private func sampleTurn(question: String, at offset: TimeInterval) -> AskTraceTurn {
        AskTraceTurn(
            id: UUID(),
            question: question,
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            duration: 1,
            spans: []
        )
    }

    private func sampleSpan(
        id: UUID,
        parent: UUID?,
        name: String,
        kind: AskTraceSpanKind,
        start: TimeInterval,
        end: TimeInterval,
        attributes: [AskTraceSpan.Attribute] = [],
        result: String? = nil
    ) -> AskTraceSpan {
        AskTraceSpan(
            id: id,
            parentID: parent,
            name: name,
            kind: kind,
            function: "test",
            fileID: "test",
            line: 1,
            start: start,
            end: end,
            status: .ok,
            attributes: attributes,
            result: result,
            events: [],
            model: nil
        )
    }

    private func posterTurn(question: String, attributes: [AskTraceSpan.Attribute]) -> AskTraceTurn {
        AskTraceTurn(
            id: UUID(),
            question: question,
            entry: .composer,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1,
            spans: [
                sampleSpan(id: UUID(), parent: nil, name: "turn", kind: .turn, start: 0, end: 1, attributes: attributes)
            ]
        )
    }
}
#endif
