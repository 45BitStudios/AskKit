#if !os(watchOS)
import AskKit
import AskKitIntents
import AskKitSurface
import BorderBeamKit
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
#if canImport(Photos)
import Photos
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
import SwiftData
import SwiftUI
import Textual
import ThinkingOrbsKit
#if canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
import VoiceGlowKit

/// Chips, the saved transcript, and a Liquid Glass composer.
/// An intent skill shows that skill's card. A reply skill shows Ask's text.
public struct AskChatView: View {
    private let assistant: AskAssistant
    private let appearance: AskChatAppearance
    private let embedsNavigation: Bool
    private let onAction: (AskAction) -> Void
    private let feedback: AskAnswerFeedback?
    private let menu: AnyView
    private let hasHostMenu: Bool

    public init(
        assistant: AskAssistant,
        appearance: AskChatAppearance = AskChatAppearance(),
        embedsNavigation: Bool = true,
        feedback: AskAnswerFeedback? = nil,
        onAction: @escaping (AskAction) -> Void = { _ in }
    ) {
        self.assistant = assistant
        self.appearance = appearance
        self.embedsNavigation = embedsNavigation
        self.feedback = feedback
        self.onAction = onAction
        self.menu = AnyView(EmptyView())
        AskCardRenderer.install()
        self.hasHostMenu = false
    }

    /// Host actions land in the top-trailing ellipsis menu with Clear chat and debug tools.
    public init<MenuContent: View>(
        assistant: AskAssistant,
        appearance: AskChatAppearance = AskChatAppearance(),
        embedsNavigation: Bool = true,
        feedback: AskAnswerFeedback? = nil,
        onAction: @escaping (AskAction) -> Void = { _ in },
        @ViewBuilder menu: () -> MenuContent
    ) {
        self.assistant = assistant
        self.appearance = appearance
        self.embedsNavigation = embedsNavigation
        self.feedback = feedback
        self.onAction = onAction
        self.menu = AnyView(menu())
        AskCardRenderer.install()
        self.hasHostMenu = true
    }

    public var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack { screen }
            } else {
                screen
            }
        }
        .modelContainer(assistant.modelContainer)
    }

    private var screen: some View {
        AskChatScreen(
            assistant: assistant,
            appearance: appearance,
            feedback: feedback,
            menu: menu,
            hasHostMenu: hasHostMenu,
            onAction: onAction
        )
    }
}

private struct AskChatScreen: View {
    let assistant: AskAssistant
    let appearance: AskChatAppearance
    let feedback: AskAnswerFeedback?
    let menu: AnyView
    let hasHostMenu: Bool
    let onAction: (AskAction) -> Void

    @Query(sort: \AskTurnRecord.createdAt) private var turns: [AskTurnRecord]
    private let activity = AskChatActivityCenter.shared
    @State private var chips: [AskChip] = []
    @State private var draft = ""
    @State private var draftImages: [AskAttachedImage] = []
    @State private var sentImages: [UUID: [AskAttachedImage]] = [:]
    /// The last pictures sent in this thread. A later "where was it taken" still reads them.
    @State private var recentPhotos: [AskAttachedImage] = []
    @State private var isThinking = false
    /// True from the voice send through the spoken answer, so Stop can cancel playback.
    @State private var voiceSpeaking = false
    @State private var turnTask: Task<Void, Never>?
    /// Optimistic send that morphs from the composer into the transcript.
    @State private var pendingSend: AskPendingSend?
    /// When true, the morph bubble's geometry source is still on the composer.
    @State private var sendFromComposer = false
    /// How far the transcript has been dragged toward the leading edge. The time sits in that gap.
    @State private var timeReveal: CGFloat = 0
    @State private var timeRevealArmed = false
    /// Frames of card pagers, in the transcript coordinate space. A sideways drag that starts there pages cards.
    @State private var pagerFrames: [CGRect] = []
    @State private var cardPaging = false
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AskComputeSelection.storageKey) private var computeRaw = AskCompute.onDevice.rawValue

    private let timeRevealLimit: CGFloat = 76
    @State private var livePages: [UUID: [AskPage]] = [:]
    @State private var replayedPages: [UUID: [AskPage]] = [:]
    /// Cards that already played their entrance, so scrolling back does not play it again.
    @State private var settledCards: Set<UUID> = []
    @State private var followUp: AskFollowUp?
    @State private var followUpTurnID: UUID?
    /// True when the thread is taller than the screen and the top of it is on screen.
    @State private var showsJumpToBottom = false
    @State private var openPhoto: AskPhotoSet?
    @State private var photoZoomID = UUID()
    @Namespace private var photoZoom
    @Namespace private var sendBubble
    @State private var library = AskLibraryGallery()
    @Namespace private var libraryZoom
    @State private var cardExpansion = AskCardExpansion()
    @Namespace private var cardZoom
    @State private var votes: [UUID: Bool]
    #if DEBUG
    @State private var showsCards = false
    @State private var showsToolkit = false
    @State private var showsTrace = false
    @State private var traceFocus: AskTraceFocus?
    @AppStorage(AskWorkedTraceSelection.storageKey) private var showsWorkedTrace = true
    #endif

    init(
        assistant: AskAssistant,
        appearance: AskChatAppearance,
        feedback: AskAnswerFeedback?,
        menu: AnyView,
        hasHostMenu: Bool,
        onAction: @escaping (AskAction) -> Void
    ) {
        self.assistant = assistant
        self.appearance = appearance
        self.feedback = feedback
        self.menu = menu
        self.hasHostMenu = hasHostMenu
        self.onAction = onAction
        _votes = State(initialValue: feedback?.votes ?? [:])
    }

    private var visibleTurns: [AskTurnRecord] {
        turns.filter { $0.thread?.assistantName == assistant.configuration.assistantName }
    }

    /// Transcript rows while a send morph is in flight. The matching stored user turn stays hidden.
    private var displayTurns: [AskTurnRecord] {
        AskSendMorph.hidingPendingUserTurn(
            visibleTurns,
            pendingText: pendingSend?.text,
            role: \.role,
            text: \.text
        )
    }

    private var title: String {
        appearance.title ?? assistant.configuration.assistantName
    }

    private var photoPresented: Binding<Bool> {
        Binding(get: { openPhoto != nil }, set: { if !$0 { openPhoto = nil } })
    }

    private var libraryPresented: Binding<Bool> {
        Binding(get: { library.presented }, set: { if !$0 { library.presented = false } })
    }

    private var libraryZoomBinding: Binding<String> {
        Binding(get: { library.zoomID }, set: { library.zoomID = $0 })
    }

    private var cardExpanded: Binding<Bool> {
        Binding(get: { cardExpansion.presented }, set: { if !$0 { cardExpansion.presented = false } })
    }

    var body: some View {
        transcript
            .overlay {
                if visibleTurns.isEmpty, pendingSend == nil, !isThinking {
                    AskEmptyPrompt(appearance: appearance, fallbackTitle: title)
                        .allowsHitTesting(false)
                }
            }
            .background {
                AskChatBackdrop(tint: appearance.tint, voiceColors: appearance.voiceColors)
                    .ignoresSafeArea()
            }
            .safeAreaBar(edge: .bottom) {
                composer
            }
            .askInlineTitle()
            .toolbar { toolbar }
            .askHiddenBarBackground()
            .navigationDestination(isPresented: photoPresented) {
                if let openPhoto {
                    let pages = openPhoto.pages
                    if pages.contains(where: { $0.id == openPhoto.startID }) {
                        AskImageViewer(pages: pages, startID: openPhoto.startID, zoomID: $photoZoomID)
                            .askZoomTransition(sourceID: photoZoomID, in: photoZoom)
                    }
                }
            }
            .navigationDestination(isPresented: libraryPresented) {
                AskPhotosGallery(
                    photos: library.photos,
                    startID: library.startID ?? "",
                    sourcePrefix: library.sourcePrefix,
                    zoomID: libraryZoomBinding
                )
                .askZoomTransition(sourceID: library.zoomID, in: libraryZoom)
            }
            .navigationDestination(isPresented: cardExpanded) {
                if let card = cardExpansion.card, let pageID = cardExpansion.pageID {
                    AskCardFullScreen(card: card)
                        .askZoomTransition(sourceID: pageID, in: cardZoom)
                }
            }
            .environment(\.libraryGallery, library)
            .environment(\.libraryZoomNamespace, libraryZoom)
            .environment(\.cardExpansion, cardExpansion)
            .environment(\.cardZoomNamespace, cardZoom)
            .environment(\.askCardStyle, .chat)
            .environment(\.askBubbleFill, appearance.assistantBubble)
            .task { chips = await assistant.chips() }
            .task {
                await AskSurfaces.refresh(access: assistant.configuration.appleAccess)
                await openQueuedSurface()
            }
            .onReceive(NotificationCenter.default.publisher(for: .askSurfaceQueued)) { _ in
                Task { await openQueuedSurface() }
            }
            .onChange(of: isThinking) { _, thinking in
                guard !thinking else { return }
                Task { await openQueuedSurface() }
            }
            #if DEBUG
            .sheet(isPresented: $showsCards) {
                AskCardGalleryScreen()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsToolkit) {
                AskCardToolkitScreen(assistant: assistant)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsTrace) {
                AskTraceScreen(showsClose: true, snippetCards: snippetCards(for:))
            }
            .sheet(item: $traceFocus) { focus in
                AskTraceScreen(showsClose: true, turnID: focus.turnID, snippetCards: snippetCards(for:))
            }
            #endif
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(displayTurns.enumerated()), id: \.element.id) { index, turn in
                        let previous = index > 0 ? displayTurns[index - 1].createdAt : nil
                        turnRow(turn, previous: previous)
                    }
                    if let pending = pendingSend {
                        pendingSendRow(pending)
                    }
                    // Follow-up keeps isThinking set after the answer is saved. The live
                    // bubble stays only while the last turn is still the question.
                    if isThinking, (visibleTurns.last?.role == "user" || pendingSend != nil) {
                        Group {
                            if activity.partial.isEmpty {
                                AskThinkingRow(
                                    title: activity.title.isEmpty ? appearance.thinkingTitle : activity.title,
                                    detail: activity.detail,
                                    phase: activity.phase
                                )
                                .id("thinking")
                            } else {
                                AskSpeechBubble(text: activity.partial, appearance: appearance)
                                    .id("streaming")
                            }
                        }
                        .modifier(AskTimeRevealShift(distance: contentShift))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
#if os(iOS) || os(visionOS)
                .background(AskChatScrollKeyboardDismiss())
#endif
            }
            // The library-photo zoom grows past the transcript. A clip here falls back to a push.
            .scrollClipDisabled()
#if !os(visionOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .defaultScrollAnchor(.bottom)
#if !os(tvOS)
            .simultaneousGesture(timeRevealDrag)
#endif
            .onScrollGeometryChange(for: Bool.self) { geometry in
                AskScrollEdge.showsJumpToBottom(
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    visibleMinY: geometry.visibleRect.minY
                )
            } action: { _, shows in
                showsJumpToBottom = shows
            }
            .overlay(alignment: .bottom) {
                jumpToBottomButton(proxy)
            }
            .onChange(of: displayTurns.count) { scrollToEnd(proxy) }
            .onChange(of: pendingSend?.id) { scrollToEnd(proxy) }
            .onChange(of: isThinking) { scrollToEnd(proxy) }
            .onChange(of: activity.partial) { scrollToEnd(proxy) }
            .onChange(of: followUp?.question) { scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy) }
        }
        .coordinateSpace(.named("AskKitTranscript"))
        .onPreferenceChange(AskPagerFrameKey.self) { pagerFrames = $0 }
    }

    /// A glass chevron above the composer. Shown at the top of a thread that does not fit.
    private func jumpToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            AskCue.tap()
            scrollToEnd(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.title3.weight(.semibold))
        }
#if !os(visionOS)
        .buttonStyle(.glass)
#else
        .buttonStyle(.bordered)
#endif
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .accessibilityLabel("Scroll to bottom")
        .padding(.bottom, 6)
        .opacity(showsJumpToBottom ? 1 : 0)
        .allowsHitTesting(showsJumpToBottom)
        .accessibilityHidden(!showsJumpToBottom)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsJumpToBottom)
    }

    private var toolbarSubtitle: String {
        (AskCompute(rawValue: computeRaw) ?? .onDevice).title
    }

    private var canClearChat: Bool {
        !visibleTurns.isEmpty && !isThinking && pendingSend == nil
    }

    private var showsMoreMenu: Bool {
        #if DEBUG
        true
        #else
        hasHostMenu || canClearChat
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                logoMark
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(toolbarSubtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .askGlass(tint: appearance.tint.opacity(0.18), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(title), \(toolbarSubtitle)")
        }
#if !os(visionOS) && !os(tvOS)
        .sharedBackgroundVisibility(.hidden)
#endif

        if showsMoreMenu {
            ToolbarItem(placement: .askTrailing) {
                Menu {
                    menu
                    #if DEBUG
                    Button("Card toolkit", systemImage: "rectangle.3.group") {
                        AskCue.tap()
                        showsToolkit = true
                    }
                    Button("Cards", systemImage: "rectangle.stack") {
                        AskCue.tap()
                        showsCards = true
                    }
                    Button("Ask trace", systemImage: "point.3.connected.trianglepath.dotted") {
                        AskCue.tap()
                        showsTrace = true
                    }
                    Toggle(isOn: $showsWorkedTrace) {
                        Label("Worked summary", systemImage: "clock")
                    }
                    #endif
                    if canClearChat {
                        Divider()
                        Button("Clear chat", systemImage: "trash", role: .destructive) {
                            AskCue.tap()
                            clear()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("More")
            }
        }
    }

    @ViewBuilder
    private var logoMark: some View {
        switch appearance.logo {
        case .symbol(let name):
            Image(systemName: name)
                .font(.body.weight(.semibold))
                .foregroundStyle(appearance.tint)
                .frame(width: 28, height: 28)
                .background(appearance.tint.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }

    /// Optimistic user bubble that receives the matched-geometry send morph.
    private func pendingSendRow(_ pending: AskPendingSend) -> some View {
        HStack {
            Spacer(minLength: 48)
            AskSendMorphBubble(text: pending.text, appearance: appearance)
                .matchedGeometryEffect(id: pending.id, in: sendBubble, isSource: !sendFromComposer)
                .opacity(sendFromComposer ? 0 : 1)
                .accessibilityHidden(sendFromComposer)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pending.text)
        .modifier(AskTimeRevealShift(distance: contentShift))
        .id(pending.id)
    }

    /// Bubbles slide toward the leading edge. The clock time stays on the trailing edge.
    private func turnRow(_ turn: AskTurnRecord, previous: Date?) -> some View {
        let clock = transcriptClock
        return VStack(alignment: .leading, spacing: 12) {
            if clock.showsMark(after: previous, date: turn.createdAt) {
                Text(clock.mark(for: turn.createdAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
            }
            bubble(turn)
            if let followUp, turn.id == followUpTurnID {
                AskFollowUpChip(question: followUp.question, tint: appearance.tint) {
                    Task { await sendFollowUp(followUp) }
                }
                .disabled(isThinking)
            }
            if let feedback, turn.id == feedbackAnchor {
                AskHelpfulRow(
                    title: feedback.title,
                    yesLabel: feedback.yesLabel,
                    noLabel: feedback.noLabel,
                    vote: votes[turn.id],
                    tint: appearance.tint,
                    onVote: { choose($0, for: turn.id) }
                )
            }
        }
        .modifier(AskTimeRevealShift(distance: contentShift))
        .overlayPreferenceValue(AskTimeAnchorKey.self) { mark in
            if let mark {
                GeometryReader { proxy in
                    Text(clock.time(for: turn.createdAt))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)
                        .frame(width: proxy.size.width, alignment: .trailing)
                        .offset(x: timeSlide)
                        .position(x: proxy.size.width / 2, y: proxy[mark.anchor].midY)
                        .opacity(timeOpacity)
                        .accessibilityLabel(clock.time(for: turn.createdAt))
                }
                .allowsHitTesting(false)
            }
        }
        .id(turn.id)
    }

    @ViewBuilder
    private func bubble(_ turn: AskTurnRecord) -> some View {
        if turn.role == "user" {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if let images = sentImages[turn.id], !images.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(images) { image in
                                AskImageThumb(image: image, zoom: photoZoom) {
                                    photoZoomID = image.id
                                    openPhoto = AskPhotoSet(images: images, startID: image.id)
                                }
                            }
                        }
                    }
                    copyable(turn.text, foreground: appearance.userForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(appearance.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .modifier(AskBubbleMenu(
                            text: turn.text,
                            fill: appearance.userBubble,
                            foreground: appearance.userForeground,
                            answer: nil
                        ))
                }
                .askTimeAnchor(priority: 2)
            }
        } else {
            assistantAnswer(turn)
        }
    }

    private func pages(for turn: AskTurnRecord) -> [AskPage] {
        if let live = livePages[turn.id], !live.isEmpty { return live }
        if let replayed = replayedPages[turn.id], !replayed.isEmpty { return replayed }
        return AskStoredPages.display(
            json: turn.pagesJSON,
            fallbackID: turn.id,
            fallbackText: turn.text,
            fallbackSpoken: turn.spoken,
            skillID: turn.skillID,
            domainID: turn.domainID,
            slotsJSON: turn.slotsJSON
        )
    }

    @ViewBuilder
    private func assistantAnswer(_ turn: AskTurnRecord) -> some View {
        let pages = pages(for: turn)
        let menu = AskAnswerMenu(
            vote: votes[turn.id],
            onVote: { choose($0, for: turn.id) },
            onTrace: { openTrace(turn) }
        )
        VStack(alignment: .leading, spacing: 8) {
            #if DEBUG
            if showsWorkedTrace, let worked = workedTrace(for: turn) {
                let summary = AskTraceViewModel.summary(turn: worked)
                AskWorkedTracePill(
                    caption: AskTraceFormatter.workedCaption(
                        duration: worked.duration,
                        toolCalls: summary.toolCalls,
                        modelCalls: summary.modelCalls
                    ),
                    symbolName: AskTraceFormatter.workedSymbol(toolCalls: summary.toolCalls)
                ) {
                    openTrace(turn)
                }
            }
            #endif
            Group {
                if pages.count > 1 {
                    AskAnswerPager(
                        pages: pages,
                        appearance: appearance,
                        onAction: performAction,
                        answerMenu: menu,
                        animatesArrival: livePages[turn.id] != nil,
                        settledCards: settledCards,
                        onSettled: { settledCards.insert($0) },
                        onPaging: { paging in
                            cardPaging = paging
                            if paging { hideTimeImmediately() }
                        }
                    )
                } else if let page = pages.first {
                    AskAnswerColumn(
                        page: page,
                        appearance: appearance,
                        onAction: performAction,
                        answerMenu: menu,
                        animatesArrival: livePages[turn.id] != nil,
                        settledCards: settledCards,
                        onSettled: { settledCards.insert($0) }
                    )
                }
            }
        }
        .task(id: turn.id) {
            guard livePages[turn.id] == nil else { return }
            let restored = await assistant.pages(for: turn.id)
            if !restored.isEmpty {
                replayedPages[turn.id] = restored
            }
        }
    }

    private func copyable(_ text: String, foreground: Color) -> some View {
        AskSelectableText(text: text, foreground: foreground)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button(chip.title) {
                                AskCue.tap()
                                Task { await sendChip(chip) }
                            }
                                .buttonStyle(.plain)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AskTintChrome.label(appearance.tint, scheme: colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AskTintChrome.capsule(appearance.tint, scheme: colorScheme), in: Capsule())
                                .disabled(isThinking)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .opacity(isThinking ? 0.72 : 1)
            }
            AskComposerField(
                appearance: appearance,
                assistantName: assistant.configuration.assistantName,
                allowedAccess: assistant.configuration.appleAccess,
                draft: $draft,
                images: $draftImages,
                isThinking: isThinking,
                voiceSpeaking: voiceSpeaking,
                onSubmit: {
                    turnTask = Task { _ = await sendDraft() }
                },
                onVoice: { text in
                    draft = text
                    turnTask = Task {
                        voiceSpeaking = true
                        defer { voiceSpeaking = false }
                        let line = await sendDraft(entry: .voice)
                        guard !Task.isCancelled, !line.isEmpty else { return }
                        await AskVoiceSpeaker.shared.speak(line)
                    }
                },
                onStop: stopRequest,
                photoZoom: photoZoom,
                onOpenPhoto: { image in
                    photoZoomID = image.id
                    openPhoto = AskPhotoSet(images: draftImages, startID: image.id)
                }
            )
            .overlay(alignment: .top) {
                if let pending = pendingSend, sendFromComposer {
                    AskSendMorphBubble(text: pending.text, appearance: appearance, fillsWidth: true)
                        .matchedGeometryEffect(id: pending.id, in: sendBubble, isSource: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.top, 4)
    }

    /// A calendar card's Pin button, or the words "Pin this", keeps the next event on the Lock Screen.
    private func performAction(_ action: AskAction) {
        guard action.id == AskPinPhrase.actionID else {
            onAction(action)
            return
        }
        guard !isThinking else { return }
        draft = action.title
        turnTask = Task { _ = await sendDraft() }
    }

    /// A Control or widget asked for a question, and maybe a Lock Screen pin, while Ask was closed.
    private func openQueuedSurface() async {
        let pin = AskSurfaceStore.shared.consumePin()
        let question = isThinking ? nil : AskSurfaceStore.shared.takeQuestion()
        if let question {
            draft = question
            _ = await sendDraft()
        }
        guard pin || question != nil else { return }
        await AskSurfaces.refresh(access: assistant.configuration.appleAccess)
        if pin {
            await AskSurfaces.pinNextEvent()
        }
    }

    private func sendDraft(entry: AskTraceEntry = .composer) async -> String {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = draftImages
        guard (!text.isEmpty || !attached.isEmpty), !isThinking else { return "" }
        guard pendingSend == nil else { return "" }
        let utterance: String
        if text.isEmpty {
            utterance = attached.count == 1 ? "Look at the attached image." : "Look at the attached images."
        } else {
            utterance = text
        }
        let morph = AskSendMorph.shouldMorph(
            text: utterance,
            imageCount: attached.count,
            reduceMotion: reduceMotion
        )
        let pending = morph ? AskPendingSend(id: UUID(), text: utterance) : nil
        if let pending {
            pendingSend = pending
            sendFromComposer = true
        }
        draft = ""
        draftImages = []
        let urls: [URL]
        if !attached.isEmpty {
            urls = attached.map(\.url)
            recentPhotos = attached
        } else if AskImageFacts.continues(utterance) {
            urls = recentPhotos.map(\.url)
        } else {
            urls = []
        }
        defer {
            if pendingSend?.id == pending?.id {
                pendingSend = nil
                sendFromComposer = false
            }
        }
        var line = ""
        let answer = Task { @MainActor in
            await runTurn {
                let result = await assistant.handle(utterance: utterance, entry: entry, images: urls)
                line = AskVoiceLine.text(from: result)
                return result
            }
        }
        if let pending {
            await playSendMorph(pending)
        }
        if Task.isCancelled {
            answer.cancel()
        }
        _ = await answer.value
        if !attached.isEmpty, let id = try? assistant.transcript().last(where: { $0.role == "user" })?.id {
            sentImages[id] = attached
        }
        return line
    }

    /// Flies the optimistic bubble from the composer into the transcript, then waits for the stored turn.
    private func playSendMorph(_ pending: AskPendingSend) async {
        await Task.yield()
        withAnimation(AskSendMorph.animation) {
            sendFromComposer = false
        }
        try? await Task.sleep(for: .milliseconds(400))
        for _ in 0..<40 {
            if Task.isCancelled { break }
            if visibleTurns.contains(where: { $0.role == "user" && $0.text == pending.text }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard pendingSend?.id == pending.id else { return }
        // Swap onto the stored bubble without a second geometry animation.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pendingSend = nil
        }
    }

    private func sendChip(_ chip: AskChip) async {
        guard !isThinking else { return }
        turnTask = Task { await runTurn { await assistant.handle(chip: chip) } }
    }

    private func runTurn(_ work: () async -> AskTurnResult) async {
        activity.title = appearance.thinkingTitle
        activity.detail = ""
        activity.phase = .thinking
        AskChatActivity.clearStream()
        isThinking = true
        followUp = nil
        let result = await work()
        guard !Task.isCancelled else { return }
        remember(result)
        AskChatActivity.clearStream()
        isThinking = false
    }

    /// Drops the in-flight answer. The question already in the thread stays.
    private func stopRequest() {
        guard isThinking || pendingSend != nil || voiceSpeaking else { return }
        AskCue.requestStopped()
        turnTask?.cancel()
        voiceSpeaking = false
        AskVoiceSpeaker.shared.stop()
        AskChatActivity.clearStream()
        activity.title = ""
        activity.detail = ""
        activity.phase = .thinking
        isThinking = false
        pendingSend = nil
        sendFromComposer = false
    }

    private func sendFollowUp(_ offer: AskFollowUp) async {
        guard !isThinking else { return }
        followUp = nil
        turnTask = Task { await runTurn { await assistant.handle(utterance: offer.question) } }
    }

    private func remember(_ result: AskTurnResult) {
        guard let id = try? assistant.transcript().last?.id else { return }
        followUp = result.followUp
        followUpTurnID = result.followUp == nil ? nil : id
        if !result.pages.isEmpty {
            livePages[id] = result.pages
        }
    }

    private var feedbackTurns: [AskFeedbackTurn] {
        visibleTurns.map { AskFeedbackTurn(id: $0.id, isUser: $0.role == "user", text: $0.text) }
    }

    private var feedbackAnchor: UUID? {
        guard feedback != nil else { return nil }
        return AskFeedback.anchorID(in: feedbackTurns)
    }

    #if DEBUG
    private func snippetCards(for trace: AskTraceTurn) async -> [AnyView] {
        let turns = (try? assistant.transcript()) ?? []
        guard let id = AskTraceStore.assistantTurn(matching: trace.question, near: trace.startedAt, turns: turns) else {
            return []
        }
        let pages = await assistant.pages(for: id)
        return pages.compactMap { $0.card?.view }
    }

    private func workedTrace(for turn: AskTurnRecord) -> AskTraceTurn? {
        let traces = AskTraceStore.live().loadAll()
        let question = AskFeedback.question(before: turn.id, in: feedbackTurns)
        guard let id = AskTraceStore.match(question: question, near: turn.createdAt, turns: traces) else {
            return nil
        }
        return traces.first { $0.id == id }
    }

    private func openTrace(_ turn: AskTurnRecord) {
        AskCue.tap()
        let question = AskFeedback.question(before: turn.id, in: feedbackTurns)
        let match = AskTraceStore.match(question: question, near: turn.createdAt, turns: AskTraceStore.live().loadAll())
        traceFocus = AskTraceFocus(turnID: match)
    }
    #else
    private func openTrace(_: AskTurnRecord) {}
    #endif

    private func choose(_ helpful: Bool, for turnID: UUID) {
        let turns = feedbackTurns
        votes = AskFeedback.votes(votes, toggling: turnID, helpful: helpful)
        feedback?.onVote(
            AskAnswerVote(
                turnID: turnID,
                helpful: votes[turnID],
                question: AskFeedback.question(before: turnID, in: turns)
            )
        )
    }

    private func clear() {
        try? assistant.clearThread()
        livePages = [:]
        replayedPages = [:]
        settledCards = []
        followUp = nil
        followUpTurnID = nil
        votes = [:]
        sentImages = [:]
        recentPhotos = []
        pendingSend = nil
        sendFromComposer = false
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let animated = !reduceMotion
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var transcriptClock: AskTranscriptClock {
        AskTranscriptClock(calendar: calendar, locale: locale, now: .now)
    }

    /// Negative in left-to-right so a leftward drag moves the bubbles aside.
    private var contentShift: CGFloat {
        layoutDirection == .rightToLeft ? timeReveal : -timeReveal
    }

    /// Positive in left-to-right so the time starts off the trailing edge and slides into the gap.
    private var timeSlide: CGFloat {
        let hidden = timeRevealLimit - timeReveal
        return layoutDirection == .rightToLeft ? -hidden : hidden
    }

    private var timeOpacity: Double {
        min(1, Double(timeReveal / 24))
    }

#if !os(tvOS)
    /// Drag toward the leading edge, the way Messages does, to show each bubble's time.
    /// A drag that starts on the card pager is left to that pager.
    private var timeRevealDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("AskKitTranscript"))
            .onChanged { value in
                if dragStartsOnCards(value.startLocation) {
                    hideTimeImmediately()
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                if !timeRevealArmed {
                    guard hypot(dx, dy) > 10, abs(dx) > abs(dy) * 1.25 else { return }
                    timeRevealArmed = true
                }
                let towardLeading = layoutDirection == .rightToLeft ? dx : -dx
                let pulled = min(max(towardLeading, 0), timeRevealLimit)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    timeReveal = pulled
                }
            }
            .onEnded { value in
                timeRevealArmed = false
                if dragStartsOnCards(value.startLocation) {
                    hideTimeImmediately()
                    return
                }
                if reduceMotion {
                    timeReveal = 0
                } else {
                    withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
                        timeReveal = 0
                    }
                }
            }
    }
#endif

    private func dragStartsOnCards(_ point: CGPoint) -> Bool {
        if cardPaging { return true }
        return pagerFrames.contains { $0.insetBy(dx: -12, dy: -12).contains(point) }
    }

    private func hideTimeImmediately() {
        guard timeReveal != 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timeReveal = 0
        }
    }
}

/// Text bubble, then the card, then the button. The card is not inside the bubble.
private struct AskAnswerColumn: View {
    let page: AskPage
    let appearance: AskChatAppearance
    let onAction: (AskAction) -> Void
    var answerMenu: AskAnswerMenu?
    var label: String?
    var animatesArrival = false
    var settledCards: Set<UUID> = []
    var onSettled: (UUID) -> Void = { _ in }

    var body: some View {
        column
            .modifier(AskPageLabel(label: label))
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !page.text.isEmpty {
                AskSpeechBubble(text: page.text, appearance: appearance, answerMenu: answerMenu)
            }
            AskCardBlock(
                page: page,
                appearance: appearance,
                onAction: onAction,
                reservesTrailingSpace: true,
                animatesArrival: animatesArrival,
                hasSettled: settledCards.contains(page.id),
                onSettled: { onSettled(page.id) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .askTimeAnchor(priority: 1)
        .askBubbleMenu(
            text: page.spoken,
            fill: appearance.assistantBubble,
            foreground: appearance.assistantForeground,
            answer: answerMenu,
            when: page.text.isEmpty
        )
    }
}

private struct AskSpeechBubble: View {
    let text: String
    let appearance: AskChatAppearance
    var answerMenu: AskAnswerMenu? = nil
    @AppStorage(AskMarkdownSelection.storageKey) private var richMarkdown = false

    var body: some View {
        HStack(alignment: .top) {
            AskSelectableText(
                text: text,
                foreground: appearance.assistantForeground,
                rich: richMarkdown
            )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appearance.assistantBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .askTimeAnchor(priority: 2)
                .modifier(AskBubbleMenu(
                    text: text,
                    fill: appearance.assistantBubble,
                    foreground: appearance.assistantForeground,
                    answer: answerMenu
                ))
            Spacer(minLength: 48)
        }
    }
}

private struct AskCardBlock: View {
    let page: AskPage
    let appearance: AskChatAppearance
    let onAction: (AskAction) -> Void
    var reservesTrailingSpace: Bool
    var animatesArrival = false
    var entrance: Double = 0
    var hasSettled = true
    var onSettled: () -> Void = {}
    @State private var cardWidth: CGFloat = 0

    /// Entrance scale/offset and long-press menus both break an App Store–style zoom match.
    private var holdsZoomSource: Bool {
        page.card?.zoomTransition == true || page.card?.expands == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card = page.card {
                card.view
                    .environment(\.askCardStyle, .chat)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: proxy.size.width, initial: true) { _, width in
                                    cardWidth = width
                                }
                        }
                    }
                    .modifier(
                        AskCardZoomSource(
                            pageID: page.id,
                            card: card,
                            enabled: card.expands && !card.zoomTransition
                        )
                    )
                    .modifier(
                        AskCardActions(
                            enabled: !holdsZoomSource,
                            text: card.shareText,
                            width: cardWidth,
                            view: card.view
                        )
                    )
                    .padding(.trailing, reservesTrailingSpace ? 48 : 0)
                if let action = card.action {
                    AskActionButton(action: action, tint: appearance.tint, onAction: onAction)
                }
            } else if reservesTrailingSpace {
                ForEach(page.actions) { action in
                    AskActionButton(action: action, tint: appearance.tint, onAction: onAction)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AskCardEntrance(
            plays: animatesArrival && !hasSettled && page.card != nil && !holdsZoomSource,
            delay: entrance,
            onSettled: onSettled
        ))
    }
}

/// Slides a transcript row aside to reveal its time. At rest the offset is not applied.
/// An offset ancestor, including a zero offset, makes a photo zoom fall back to a push.
private struct AskTimeRevealShift: ViewModifier {
    var distance: CGFloat

    func body(content: Content) -> some View {
        if distance == 0 {
            content
        } else {
            content.offset(x: distance)
        }
    }
}

/// A new card rises into its place. The slot is already reserved, so the transcript does not jump.
private struct AskCardEntrance: ViewModifier {
    var plays: Bool
    var delay: Double
    var onSettled: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil until the entrance decides. History and Reduce Motion stay shown on the first frame.
    @State private var revealed: Bool?
    /// Stays hidden while the parent records that this card has started, so that update does not snap it in.
    @State private var held = false

    private var shown: Bool {
        if let revealed { return revealed }
        if held { return false }
        return !plays || reduceMotion
    }

    /// A settled card has no scale, offset, or opacity. Those effects block a zoom from a photo inside it.
    @State private var settled = false

    private var lifting: Bool {
        if settled { return false }
        if held { return true }
        return plays && !reduceMotion && revealed == nil
    }

    func body(content: Content) -> some View {
        Group {
            if lifting {
                content
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : 0.96, anchor: .top)
                    .offset(y: shown ? 0 : 16)
            } else {
                content
            }
        }
        .onAppear(perform: arrive)
    }

    private func arrive() {
        guard revealed == nil, !held else { return }
        guard plays, !reduceMotion else {
            revealed = true
            return
        }
        held = true
        onSettled()
        withAnimation(.spring(duration: 0.42, bounce: 0.18).delay(delay)) {
            revealed = true
        } completion: {
            settled = true
        }
    }
}

/// Long-press a card to share a picture of it, save that picture, or copy its words.
struct AskCardActions: ViewModifier {
    var enabled = true
    var text: String
    var width: CGFloat
    var view: AnyView

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var share: AskCardExport?
    @State private var saveNote = ""
    @State private var showsSaveNote = false

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
            menu(content)
        }
    }

    private func menu(_ content: Content) -> some View {
        content
            .contextMenu {
                Button("Share", systemImage: "square.and.arrow.up") {
                    AskCue.tap()
                    let items = exportItems()
                    guard !items.isEmpty else { return }
                    share = AskCardExport(items: items)
                }
                Button("Save", systemImage: "square.and.arrow.down") {
                    AskCue.tap()
                    guard let image = renderedImage() else {
                        note("The card could not be saved.")
                        return
                    }
                    Task { await save(image) }
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    copy()
                    AskCue.tap()
                }
            } preview: {
                cardPreview
            }
            .sheet(item: $share) { export in
                AskCardActivityView(items: export.items)
            }
            .alert("Photos", isPresented: $showsSaveNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveNote)
            }
    }

    /// A picture of the card, the same kind of preview a held photo uses. The live card has no size in the menu, and a map does not draw there.
    private var cardPreview: some View {
        let fitted = width > 1 ? min(width, 320) : 320
        let image = renderedImage()
        return Group {
            if let image, image.size.width > 1, image.size.height > 1 {
                Image(askImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: fitted)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                view
                    .frame(width: fitted, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, colorScheme)
            }
        }
    }

    private func exportItems() -> [Any] {
        var items: [Any] = []
        if let image = renderedImage() { items.append(image) }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { items.append(line) }
        return items
    }

    private func copy() {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        AskPasteboard.copy(text: line.isEmpty ? nil : line, png: renderedImage().flatMap(AskPlatform.pngData))
    }

    private func save(_ image: AskPlatformImage) async {
#if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            note("AskKit doesn't have permission to add photos.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            note("The card could not be saved.")
        }
#else
        _ = image
        note("Photos isn't available on this device.")
#endif
    }

    private func renderedImage() -> AskPlatformImage? {
        let fitted = width > 1 ? width : 300
        let content = view
            .frame(width: fitted, alignment: .leading)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale > 0 ? displayScale : 2
        renderer.proposedSize = ProposedViewSize(width: fitted, height: nil)
        return renderer.askImage
    }

    private func note(_ message: String) {
        saveNote = message
        showsSaveNote = true
    }
}

struct AskCardExport: Identifiable {
    let id = UUID()
    var items: [Any]
}

/// Names a page only when several answers share one reply.
private struct AskPageLabel: ViewModifier {
    var label: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// One speech bubble, then the cards. The next card stays in view so the row can be paged.
private struct AskAnswerPager: View {
    let pages: [AskPage]
    let appearance: AskChatAppearance
    let onAction: (AskAction) -> Void
    var answerMenu: AskAnswerMenu?
    var animatesArrival = false
    var settledCards: Set<UUID> = []
    var onSettled: (UUID) -> Void = { _ in }
    var onPaging: (Bool) -> Void = { _ in }

    /// Room left at the trailing edge so the next card is visible.
    private let peek: CGFloat = 56
    private let cardSpacing: CGFloat = 12

    @State private var pageID: UUID?

    private var cardPages: [AskPage] { pages.filter { $0.card != nil } }

    private var speech: String {
        pages.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var looseActions: [AskAction] {
        pages.filter { $0.card == nil }.flatMap(\.actions)
    }

    private var selectedID: UUID? { pageID ?? cardPages.first?.id }

    private var positionLabel: String {
        let index = cardPages.firstIndex { $0.id == selectedID } ?? 0
        return "Card \(index + 1) of \(cardPages.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !speech.isEmpty {
                AskSpeechBubble(text: speech, appearance: appearance, answerMenu: answerMenu)
            }
            if cardPages.count > 1 {
                cardPager
            } else if let page = cardPages.first {
                AskCardBlock(
                    page: page,
                    appearance: appearance,
                    onAction: onAction,
                    reservesTrailingSpace: true,
                    animatesArrival: animatesArrival,
                    hasSettled: settledCards.contains(page.id),
                    onSettled: { onSettled(page.id) }
                )
            }
            ForEach(looseActions) { action in
                AskActionButton(action: action, tint: appearance.tint, onAction: onAction)
            }
        }
        .askTimeAnchor(priority: 1)
        .askBubbleMenu(
            text: pages.map(\.spoken).filter { !$0.isEmpty }.joined(separator: "\n\n"),
            fill: appearance.assistantBubble,
            foreground: appearance.assistantForeground,
            answer: answerMenu,
            when: speech.isEmpty
        )
    }

    private var cardPager: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(Array(cardPages.enumerated()), id: \.element.id) { index, page in
                        AskCardBlock(
                            page: page,
                            appearance: appearance,
                            onAction: onAction,
                            reservesTrailingSpace: false,
                            animatesArrival: animatesArrival,
                            entrance: Double(index) * 0.07,
                            hasSettled: settledCards.contains(page.id),
                            onSettled: { onSettled(page.id) }
                        )
                        .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                            max(width - peek, 0)
                        }
                        .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $pageID)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollPhaseChange { _, phase in
                onPaging(phase != .idle)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AskPagerFrameKey.self,
                        value: [proxy.frame(in: .named("AskKitTranscript"))]
                    )
                }
            }
            .onAppear {
                if pageID == nil { pageID = cardPages.first?.id }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cards")
            .accessibilityValue(positionLabel)
            .accessibilityHint("Swipe sideways. The next card is visible.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Next card") { step(1) }
            .accessibilityAction(named: "Previous card") { step(-1) }
            HStack(spacing: 6) {
                ForEach(cardPages) { page in
                    Circle()
                        .fill(page.id == selectedID ? appearance.tint : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    private func step(_ delta: Int) {
        let ids = cardPages.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectedID
        guard let index = ids.firstIndex(of: current ?? ids[0]) else { return }
        let next = min(max(index + delta, 0), ids.count - 1)
        pageID = ids[next]
    }
}

private struct AskActionButton: View {
    let action: AskAction
    let tint: Color
    let onAction: (AskAction) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action.title) {
            AskCue.tap()
            onAction(action)
        }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AskTintChrome.label(tint, scheme: colorScheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AskTintChrome.capsule(tint, scheme: colorScheme), in: Capsule())
            .accessibilityLabel(action.title)
    }
}

private struct AskSelectableText: View {
    let text: String
    let foreground: Color
    var rich = false

    var body: some View {
        Group {
            if rich {
                StructuredText(markdown: text, syntaxExtensions: [.math])
                    .textual.structuredTextStyle(.default)
#if !os(tvOS) && !os(watchOS)
                    .textual.textSelection(.enabled)
#endif
            } else {
                Text(text)
            }
        }
        .font(.body)
        .foregroundStyle(foreground)
    }
}

/// Long-press actions. The preview is the bubble, so the words stay inside it.
private struct AskAnswerMenu {
    var vote: Bool?
    var onVote: (Bool) -> Void
    var onTrace: () -> Void
}

private struct AskBubbleMenu: ViewModifier {
    var text: String
    var fill: Color
    var foreground: Color
    var answer: AskAnswerMenu?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                AskPasteboard.copy(text: AskGuide.plainSpeech(text))
                AskCue.tap()
            }
            if let answer {
                #if DEBUG
                Button("View Trace", systemImage: "point.3.connected.trianglepath.dotted") {
                    answer.onTrace()
                }
                #endif
                Divider()
                Button {
                    AskCue.tap()
                    answer.onVote(true)
                } label: {
                    Label("Good response", systemImage: answer.vote == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                Button {
                    AskCue.tap()
                    answer.onVote(false)
                } label: {
                    Label("Bad response", systemImage: answer.vote == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
            }
        } preview: {
            Text(text)
                .font(.body)
                .foregroundStyle(foreground)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 280, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

#if DEBUG
private struct AskTraceFocus: Identifiable {
    let id = UUID()
    var turnID: UUID?
}
#endif

private struct AskFollowUpChip: View {
    let question: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            AskCue.tap()
            action()
        } label: {
            Text(question)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AskTintChrome.label(tint, scheme: colorScheme))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AskTintChrome.capsule(tint, scheme: colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question)
        .accessibilityHint("Asks this next")
    }
}

private struct AskImageThumb: View {
    var image: AskAttachedImage
    var zoom: Namespace.ID
    var onOpen: () -> Void
    var onRemove: (() -> Void)?

    @State private var share: AskCardExport?
    @State private var saveNote = ""
    @State private var showsSaveNote = false

    private var picture: AskPlatformImage? {
        AskPlatformImage(contentsOfFile: image.url.path)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard picture != nil else { return }
                AskCue.tap()
                onOpen()
            } label: {
                thumb
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .matchedTransitionSource(id: image.id, in: zoom) { source in
                        source.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            }
            .buttonStyle(.plain)
            .contextMenu {
                imageActions
            } preview: {
                preview
            }
            .accessibilityLabel(image.name)
            .accessibilityHint("Shows the photo. Hold for copy, share, and save.")
            .accessibilityAction(named: "Copy") { copyPicture() }
            .accessibilityAction(named: "Share") { sharePicture() }
            .accessibilityAction(named: "Save") { savePicture() }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(image.name)")
                .offset(x: 6, y: -6)
            }
        }
        .sheet(item: $share) { export in
            AskCardActivityView(items: export.items)
        }
        .alert("Photos", isPresented: $showsSaveNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveNote)
        }
    }

    @ViewBuilder
    private var imageActions: some View {
        Button("Copy", systemImage: "doc.on.doc") { copyPicture() }
        Button("Share", systemImage: "square.and.arrow.up") { sharePicture() }
        Button("Save", systemImage: "square.and.arrow.down") { savePicture() }
        if onRemove != nil {
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                AskCue.tap()
                onRemove?()
            }
        }
    }

    private var preview: some View {
        Group {
            if let picture {
                Image(askImage: picture)
                    .resizable()
                    .scaledToFit()
            } else {
                thumb
            }
        }
        .frame(width: 280, height: 360)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var thumb: some View {
        if let picture {
            Image(askImage: picture)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AskPlatform.tertiaryFill)
        }
    }

    private func copyPicture() {
        guard let picture else { return }
        AskImageActions.copy(picture)
        AskCue.tap()
    }

    private func sharePicture() {
        guard let picture else { return }
        AskCue.tap()
        share = AskCardExport(items: [picture])
    }

    private func savePicture() {
        guard let picture else { return }
        AskCue.tap()
        Task { await noteSave(of: picture) }
    }

    private func noteSave(of picture: AskPlatformImage) async {
        if let message = await AskImageActions.save(picture) {
            saveNote = message
            showsSaveNote = true
        }
    }
}

/// The pictures that open together, starting from the one that was tapped.
private struct AskPhotoSet: Equatable {
    var images: [AskAttachedImage]
    var startID: UUID

    var pages: [AskImagePage] {
        images.compactMap { image in
            guard let picture = AskPlatformImage(contentsOfFile: image.url.path) else { return nil }
            return AskImagePage(id: image.id, picture: picture, name: image.name)
        }
    }
}

private struct AskImagePage: Identifiable {
    var id: UUID
    var picture: AskPlatformImage
    var name: String
}

/// Photos opened from a thumbnail. Several swipe. Pinch to look closer. Double-tap returns to fit.
private struct AskImageViewer: View {
    var pages: [AskImagePage]
    var startID: UUID
    @Binding var zoomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var pageID: UUID
    @State private var drag: CGFloat = 0
    @State private var scales: [UUID: CGFloat] = [:]
    @State private var bases: [UUID: CGFloat] = [:]
    @State private var share: AskCardExport?
    @State private var saveNote = ""
    @State private var showsSaveNote = false

    init(pages: [AskImagePage], startID: UUID, zoomID: Binding<UUID>) {
        self.pages = pages
        self.startID = startID
        _zoomID = zoomID
        _pageID = State(initialValue: startID)
    }

    private var pageIndex: Int {
        pages.firstIndex { $0.id == pageID } ?? 0
    }

    private var current: AskImagePage? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : pages.first
    }

    private var currentScale: CGFloat {
        scales[pageID] ?? 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        AskImagePageView(
                            page: page,
                            position: index + 1,
                            count: pages.count,
                            scale: scaleBinding(page.id),
                            base: baseBinding(page.id)
                        )
                        .frame(width: width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(pageIndex) * width + (currentScale > 1 ? 0 : drag))
#if os(tvOS)
                .onMoveCommand { direction in
                    // The remote's left and right swipes page the pictures.
                    page(direction == .left ? -1 : direction == .right ? 1 : 0)
                }
#else
                .simultaneousGesture(paging)
#endif
            }
            if pages.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(pages) { page in
                            Circle()
                                .fill(page.id == pageID ? Color.white : Color.white.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: pageID) { _, id in
            zoomID = id
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .askLeading) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .askTrailing) {
                Button("Copy", systemImage: "doc.on.doc") { copyPicture() }
            }
            ToolbarItem(placement: .askTrailing) {
                Button("Save", systemImage: "square.and.arrow.down") { savePicture() }
            }
            ToolbarItem(placement: .askTrailing) {
                Button("Share", systemImage: "square.and.arrow.up") { sharePicture() }
            }
        }
        .askHiddenBarBackground()
        .preferredColorScheme(.dark)
        .sheet(item: $share) { export in
            AskCardActivityView(items: export.items)
        }
        .alert("Photos", isPresented: $showsSaveNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveNote)
        }
    }

#if os(tvOS)
    private func page(_ step: Int) {
        guard step != 0, pages.count > 1 else { return }
        let next = min(max(pageIndex + step, 0), pages.count - 1)
        withAnimation(.snappy(duration: 0.28)) {
            pageID = pages[next].id
        }
    }
#else
    private var paging: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard currentScale <= 1, pages.count > 1 else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                let travel = value.predictedEndTranslation.width
                var next = pageIndex
                if currentScale <= 1, pages.count > 1 {
                    if travel < -48 { next = min(pageIndex + 1, pages.count - 1) }
                    if travel > 48 { next = max(pageIndex - 1, 0) }
                }
                withAnimation(.snappy(duration: 0.28)) {
                    if pages.indices.contains(next) {
                        pageID = pages[next].id
                    }
                    drag = 0
                }
            }
    }
#endif

    private func scaleBinding(_ id: UUID) -> Binding<CGFloat> {
        Binding(get: { scales[id] ?? 1 }, set: { scales[id] = $0 })
    }

    private func baseBinding(_ id: UUID) -> Binding<CGFloat> {
        Binding(get: { bases[id] ?? 1 }, set: { bases[id] = $0 })
    }

    private func copyPicture() {
        guard let picture = current?.picture else { return }
        AskImageActions.copy(picture)
        AskCue.tap()
    }

    private func sharePicture() {
        guard let picture = current?.picture else { return }
        AskCue.tap()
        share = AskCardExport(items: [picture])
    }

    private func savePicture() {
        guard let picture = current?.picture else { return }
        AskCue.tap()
        Task {
            if let message = await AskImageActions.save(picture) {
                saveNote = message
                showsSaveNote = true
            }
        }
    }
}

private struct AskImagePageView: View {
    var page: AskImagePage
    var position: Int
    var count: Int
    @Binding var scale: CGFloat
    @Binding var base: CGFloat

    var body: some View {
        Image(askImage: page.picture)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
#if !os(tvOS) && !os(watchOS)
            .gesture(zoom)
#endif
            .onTapGesture(count: 2) {
                base = 1
                scale = 1
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityLabel(count > 1 ? "\(page.name), \(position) of \(count)" : page.name)
    }

#if !os(tvOS) && !os(watchOS)
    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(base * value.magnification, 1), 4)
            }
            .onEnded { value in
                let next = min(max(base * value.magnification, 1), 4)
                base = next
                scale = next
            }
    }
#endif
}

enum AskImageActions {
    static func copy(_ picture: AskPlatformImage) {
        guard let data = AskPlatform.pngData(picture) else { return }
        AskPasteboard.copy(png: data)
    }

    /// Nil when the photo is in the library. A string is the reason it was not saved.
    static func save(_ picture: AskPlatformImage) async -> String? {
#if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return "AskKit doesn't have permission to add photos."
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: picture)
            }
            return nil
        } catch {
            return "The photo could not be saved."
        }
#else
        _ = picture
        return "Photos isn't available on this device."
#endif
    }
}

#if os(iOS)
private struct AskCameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: AskCameraPicker

        init(_ parent: AskCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let picture = (info[.originalImage] as? AskPlatformImage)
            if let data = picture?.jpegData(compressionQuality: 0.85) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

private struct AskComposerField: View {
    let appearance: AskChatAppearance
    let assistantName: String
    let allowedAccess: AskAppleAccess
    @Binding var draft: String
    @Binding var images: [AskAttachedImage]
    let isThinking: Bool
    let voiceSpeaking: Bool
    let onSubmit: () -> Void
    let onVoice: (String) -> Void
    let onStop: () -> Void
    let photoZoom: Namespace.ID
    let onOpenPhoto: (AskAttachedImage) -> Void

    @State private var speech = AskSpeechDictation()
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var showsFiles = false
#if !os(tvOS) && !os(watchOS)
    @State private var photoItems: [PhotosPickerItem] = []
#endif
    @State private var voiceAlert: String?
    @State private var preferredCompute = AskComputeSelection.current
#if ASK_FOUNDATION_MODELS
    @State private var onDeviceModel = SystemLanguageModel.default
    @State private var cloudModel = PrivateCloudComputeLanguageModel()
#endif
    @State private var network = AskNetworkStatus.shared
    @State private var showsModel = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = 26

    /// Apple TV and Apple Watch have no Foundation Models, so neither model is ever available there.
    private var onDeviceAvailable: Bool {
#if ASK_FOUNDATION_MODELS
        onDeviceModel.isAvailable
#else
        false
#endif
    }

    private var cloudAvailable: Bool {
#if ASK_FOUNDATION_MODELS
        cloudModel.isAvailable
#else
        false
#endif
    }

    private var fieldIsBlank: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !speech.isRecording && (!fieldIsBlank || !images.isEmpty)
    }

    /// The beam is the resting state of an empty field. Typing, a photo, or the keyboard hides it.
    private var showsBeam: Bool {
        !focused && fieldIsBlank && images.isEmpty
    }

    private var beamHueShift: Double {
        AskBeamTint.shift(tint: appearance.tint, override: appearance.voiceColors)
    }

    private var showsSend: Bool {
        !appearance.showsMicrophone || !speech.isRecording
    }

    var body: some View {
        field
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            network.start()
        }
        .onDisappear {
            speech.stop()
            resignKeyboard()
        }
        .alert("Voice", isPresented: voiceAlertPresented) {
            Button("OK", role: .cancel) { voiceAlert = nil }
        } message: {
            Text(voiceAlert ?? "")
        }
        .sheet(isPresented: $showsModel) {
            AskModelSheet(
                tint: appearance.tint,
                assistantName: assistantName,
                allowed: allowedAccess,
                running: runningCompute,
                onDeviceAvailable: onDeviceAvailable,
                cloudAvailable: cloudAvailable && network.isOnline,
                changesModel: !isThinking,
                onSelect: selectCompute
            )
        }
#if !os(tvOS) && !os(watchOS)
        .photosPicker(
            isPresented: $showsPhotos,
            selection: $photoItems,
            maxSelectionCount: max(AskImageFile.maximumCount - images.count, 1),
            selectionBehavior: .ordered,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await addPhotos(items) }
        }
        .fileImporter(
            isPresented: $showsFiles,
            allowedContentTypes: AskImageFile.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            addFiles(urls)
        }
#endif
#if os(iOS)
        .askFullScreenCover(isPresented: $showsCamera) {
            AskCameraPicker { data in
                addImageData(data, name: "Photo")
            }
            .ignoresSafeArea()
        }
#endif
    }

    private var field: some View {
        VoiceGlow(
            type: .standard,
            levelProvider: speech.levelSource(),
            active: speech.isRecording,
            theme: .dark,
            cornerRadius: Double(cornerRadius),
            options: glowOptions
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if !images.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(images) { image in
                            AskImageThumb(image: image, zoom: photoZoom, onOpen: { onOpenPhoto(image) }) {
                                remove(image)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                TextField(appearance.placeholder, text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .focused($focused)
                    .textFieldStyle(.plain)
#if !os(macOS)
                    .textInputAutocapitalization(.sentences)
#endif
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(isThinking)
                controls
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .askGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                Color.clear
                    .borderBeam(
                        .md,
                        colorVariant: .ocean,
                        theme: .auto,
                        active: showsBeam,
                        borderRadius: Double(cornerRadius),
                        hueRange: 18,
                        hueOffset: beamHueShift
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

#if !os(tvOS) && !os(watchOS)
    private var addButton: some View {
        Menu {
#if os(iOS)
            Button("Take Photo", systemImage: "camera") {
                AskCue.tap()
                showsCamera = true
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
#endif
            Button("Attach Photo", systemImage: "photo") {
                AskCue.tap()
                showsPhotos = true
            }
            Button("Add File", systemImage: "doc") {
                AskCue.tap()
                showsFiles = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(appearance.tint)
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(isThinking || images.count >= AskImageFile.maximumCount)
        .accessibilityLabel("Add")
        .accessibilityHint("Take a photo, attach up to four photos, or add image files")
    }
#endif

#if !os(tvOS) && !os(watchOS)
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard images.count < AskImageFile.maximumCount else { return }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            addImageData(data, name: "Photo")
        }
    }
#endif

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            guard images.count < AskImageFile.maximumCount else { break }
            guard let stored = AskImageFile.storeCopy(of: url) else { continue }
            images.append(AskAttachedImage(url: stored, name: url.deletingPathExtension().lastPathComponent))
        }
    }

    private func addImageData(_ data: Data, name: String) {
        guard images.count < AskImageFile.maximumCount else { return }
        guard let stored = AskImageFile.store(data: data, preferredName: name) else { return }
        images.append(AskAttachedImage(url: stored, name: name))
    }

    private func remove(_ image: AskAttachedImage) {
        images.removeAll { $0.id == image.id }
        try? FileManager.default.removeItem(at: image.url)
    }

    private var controls: some View {
        HStack(spacing: 0) {
#if !os(tvOS) && !os(watchOS)
            addButton
                .padding(.leading, 4)
#endif
            modelButton
                .padding(.leading, 4)
            Spacer(minLength: 8)
            if appearance.showsMicrophone, !isThinking, !voiceSpeaking {
                if speech.isRecording {
                    recordingButton
                        .transition(buttonTransition)
                } else {
                    voiceButton
                        .transition(buttonTransition)
                    microphoneButton
                        .transition(buttonTransition)
                }
            }
            if isThinking || voiceSpeaking {
                stopRequestButton
                    .transition(buttonTransition)
            } else if showsSend {
                sendButton
                    .transition(buttonTransition)
            }
        }
        .animation(controlAnimation, value: speech.isRecording)
        .animation(controlAnimation, value: canSend)
        .animation(controlAnimation, value: isThinking)
    }

    /// The model the next turn will call. The saved choice stays put when this falls back.
    private var runningCompute: AskCompute {
        AskComputeChoice.resolved(
            preferred: preferredCompute,
            onDevice: onDeviceAvailable,
            cloud: cloudAvailable,
            online: network.isOnline
        )
    }

    private var modelButton: some View {
        Button {
            AskCue.tap()
            showsModel = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: runningCompute.symbolName)
                    .accessibilityHidden(true)
                Text(runningCompute.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AskPlatform.tertiaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(runningCompute.accessibilityLabel)
        .accessibilityHint("Opens model, tools, streaming, rich text, and Private Cloud options")
    }

    private func selectCompute(_ choice: AskCompute) {
        guard choice != preferredCompute else { return }
        preferredCompute = choice
        AskComputeSelection.current = choice
        AskCue.tap()
    }

    private var voiceButton: some View {
        Button {
            AskCue.tap()
            Task { await startListening() }
        } label: {
            roundControl(systemName: "waveform", foreground: .white, fill: appearance.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice")
        .accessibilityHint("Listens, then asks when you pause")
    }

    private var microphoneButton: some View {
        Button {
            AskCue.tap()
            Task { await startRecording() }
        } label: {
            roundControl(systemName: "mic.fill", foreground: .white, fill: appearance.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Microphone")
    }

    private var recordingButton: some View {
        Button {
            speech.stop()
        } label: {
            roundControl(systemName: "stop.fill", foreground: .white, fill: .red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isListening ? "Stop listening" : "Stop dictation")
    }

    private var stopRequestButton: some View {
        Button(action: onStop) {
            roundControl(systemName: "stop.fill", foreground: .white, fill: .red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
        .accessibilityHint(voiceSpeaking && !isThinking ? "Stops the spoken answer" : "Stops the request that is running")
    }

    private func roundControl(systemName: String, foreground: Color, fill: Color) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.bold))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(fill, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: sendSymbol)
                .font(.body.weight(.bold))
                .rotationEffect(.degrees(sendRotation))
                .foregroundStyle(canSend ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
                .background(canSend ? appearance.tint : AskPlatform.tertiaryFill, in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send")
        .animation(controlAnimation, value: canSend)
    }

    private var sendSymbol: String {
        reduceMotion && !canSend ? "arrow.down" : "arrow.up"
    }

    private var sendRotation: Double {
        reduceMotion || canSend ? 0 : 180
    }

    private var buttonTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    private var controlAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.25)
    }

    private func startListening() async {
        resignKeyboard()
        await speech.listen(onPartial: { draft = $0 }, onUtterance: onVoice) { message in
            voiceAlert = message
        }
    }

    private func startRecording() async {
        resignKeyboard()
        await speech.start(startingWith: draft, onPartial: { draft = $0 }) { message in
            voiceAlert = message
        }
    }

    private func send() {
        speech.stop()
        speech.playSendCue()
        resignKeyboard()
        onSubmit()
    }

    private func resignKeyboard() {
        focused = false
#if os(iOS) || os(visionOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    private var voiceAlertPresented: Binding<Bool> {
        Binding(get: { voiceAlert != nil }, set: { if !$0 { voiceAlert = nil } })
    }

    /// Empty `voiceColors` builds seven shades of the sample tint.
    /// The dark theme keeps those shades visible on the glass field.
    private var glowOptions: VoiceGlowOptions {
        var options = VoiceGlowOptions()
        let colors = AskVoicePalette.colors(tint: appearance.tint, override: appearance.voiceColors)
            .compactMap(Self.glowColor)
        if !colors.isEmpty {
            options.colors = Array(colors)
        }
        return options
    }

    private static func glowColor(_ color: Color) -> VoiceGlowColor? {
        guard let parts = AskColorParts.rgb(color) else { return nil }
        return VoiceGlowColor(Double(parts.red) * 255, Double(parts.green) * 255, Double(parts.blue) * 255)
    }
}

/// Model, tools, streaming, rich text, and Private Cloud options. Opened from the composer capsule.
private struct AskModelSheet: View {
    var tint: Color
    var assistantName: String
    var allowed: AskAppleAccess
    var running: AskCompute
    var onDeviceAvailable: Bool
    var cloudAvailable: Bool
    /// False while a turn is running. Streaming and rich text stay editable.
    var changesModel: Bool
    var onSelect: (AskCompute) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AskModelChoiceSection(
                    running: running,
                    onDeviceAvailable: onDeviceAvailable,
                    cloudAvailable: cloudAvailable,
                    enabled: changesModel,
                    onSelect: onSelect
                )
                AskReplyOptionsSection()
                AskModelToolsSection(
                    assistantName: assistantName,
                    allowed: allowed,
                    enabled: changesModel
                )
                if running == .privateCloud {
#if ASK_FOUNDATION_MODELS
                    AskCloudOptionsSections(tint: tint, enabled: changesModel)
#endif
                }
            }
            .tint(tint)
#if !os(tvOS)
            .scrollContentBackground(.hidden)
#endif
            .navigationTitle("Model")
            .askInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        AskCue.tap()
                        dismiss()
                    }
                }
            }
            .askHiddenBarBackground()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }
}

/// On-Device or Private Cloud. The check sits on the model the next turn will run.
private struct AskModelChoiceSection: View {
    var running: AskCompute
    var onDeviceAvailable: Bool
    var cloudAvailable: Bool
    var enabled: Bool
    var onSelect: (AskCompute) -> Void

    var body: some View {
        Section {
            Picker("Model", selection: selection) {
                ForEach(AskCompute.allCases, id: \.self) { choice in
                    Label(choice.title, systemImage: choice.symbolName)
                        .tag(choice)
                        .disabled(!isAvailable(choice))
                        .accessibilityLabel(choice.accessibilityLabel)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(!enabled)
        } header: {
            Text("Model")
        }
    }

    private var selection: Binding<AskCompute> {
        Binding(get: { running }, set: { onSelect($0) })
    }

    private func isAvailable(_ choice: AskCompute) -> Bool {
        switch choice {
        case .onDevice: onDeviceAvailable
        case .privateCloud: cloudAvailable
        }
    }
}

/// Streaming and rich text. Both stay available while a turn is running.
private struct AskReplyOptionsSection: View {
    @State private var streams = AskStreamSelection.isOn
    @AppStorage(AskMarkdownSelection.storageKey) private var markdown = false

    var body: some View {
        Section {
            Toggle(isOn: $streams) {
                Label("Streaming", systemImage: "text.bubble")
            }
            .onChange(of: streams) { _, isOn in
                AskStreamSelection.isOn = isOn
                if !isOn {
                    AskChatActivity.clearStream()
                }
                AskCue.tap()
            }
            .accessibilityHint("Shows the answer while it is written. Off keeps the thinking status until the answer is ready.")
            Toggle(isOn: $markdown) {
                Label("Rich text", systemImage: "doc.richtext")
            }
            .onChange(of: markdown) { _, _ in
                AskCue.tap()
            }
            .accessibilityHint("Renders Markdown in answer bubbles and asks the model for lists, tables, and math when that helps.")
        } footer: {
            Text("Streaming shows the answer while it is written. Rich text renders lists, tables, and math.")
        }
    }
}

/// The Apple sources this assistant allows, and which of them the next reply may read.
private struct AskModelToolsSection: View {
    var assistantName: String
    var allowed: AskAppleAccess
    var enabled: Bool
    @State private var selected: AskAppleAccess

    init(assistantName: String, allowed: AskAppleAccess, enabled: Bool) {
        self.assistantName = assistantName
        self.allowed = allowed
        self.enabled = enabled
        _selected = State(initialValue: AskAppleSelection.active(allowed: allowed, for: assistantName))
    }

    var body: some View {
        if sources.isEmpty {
            Section {
                Text("This assistant has not turned on any Apple sources.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tools")
            }
        } else {
            Section {
                ForEach(sources) { source in
                    Toggle(isOn: binding(for: source)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                Text(source.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: source.symbol)
                        }
                    }
                    .disabled(!enabled)
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("A reply uses the tools that are on, including any tools the skill adds. Chip taps do not use them.")
            }
        }
    }

    private var sources: [AskAppleSource] {
        AskAppleSource.catalog.filter { allowed.contains($0.access) }
    }

    private func binding(for source: AskAppleSource) -> Binding<Bool> {
        Binding(
            get: { selected.contains(source.access) },
            set: { isOn in
                var next = selected
                if isOn {
                    next.insert(source.access)
                } else {
                    next.remove(source.access)
                }
                let saved = AskAppleSelection.update(next, allowed: allowed, for: assistantName)
                guard saved != selected else { return }
                selected = saved
                AskCue.tap()
            }
        )
    }
}

#if ASK_FOUNDATION_MODELS
/// Reasoning, temperature, response length, and the daily limit. Shown when Private Cloud will run.
private struct AskCloudOptionsSections: View {
    var tint: Color
    var enabled: Bool
    @State private var options = AskCloudSettings.current
    @State private var model = PrivateCloudComputeLanguageModel()

    var body: some View {
        Group {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quotaLine)
                    if let reset = model.quotaUsage.resetDate {
                        Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
                    Button {
                        AskCue.tap()
                        suggestion.show()
                    } label: {
                        Text("Raise limit")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Daily limit")
        }

        Section {
            Picker("Reasoning", selection: $options.reasoning) {
                ForEach(AskCloudReasoning.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.menu)
            Text(options.reasoning.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Light answers sooner. Deep spends longer before it answers.")
        }

        Section {
            Toggle("Temperature", isOn: temperatureEnabled)
            if options.temperature != nil {
                HStack {
                    Slider(value: temperatureValue, in: 0...1)
                        .tint(tint)
                    Text(temperatureValue.wrappedValue, format: .number.precision(.fractionLength(2)))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        } header: {
            Text("Sampling")
        } footer: {
            Text("Lower stays closer to the likely answer. Higher varies more. Off uses the model's own setting.")
        }

        Section {
            Picker("Response length", selection: $options.length) {
                ForEach(AskCloudLength.allCases, id: \.self) { length in
                    Text(length.title)
                        .tag(length)
                        .accessibilityLabel(length.accessibilityLabel)
                }
            }
            .pickerStyle(.menu)
        } footer: {
            Text("A shorter cap stops a long answer early. Automatic uses the room left in the context.")
        }
        }
        .disabled(!enabled)
        .onChange(of: options) { _, newValue in
            AskCloudSettings.current = newValue
        }
    }

    private var quotaLine: String {
        switch model.quotaUsage.status {
        case .limitReached:
            AskCloudQuotaText.line(reached: true, approaching: false)
        case .belowLimit(let below):
            AskCloudQuotaText.line(reached: false, approaching: below.isApproachingLimit)
        @unknown default:
            AskCloudQuotaText.line(reached: false, approaching: false)
        }
    }

    private var temperatureEnabled: Binding<Bool> {
        Binding(
            get: { options.temperature != nil },
            set: { isOn in
                options.temperature = isOn ? (options.temperature ?? 0.5) : nil
            }
        )
    }

    private var temperatureValue: Binding<Double> {
        Binding(
            get: { options.temperature ?? 0.5 },
            set: { options.temperature = $0 }
        )
    }
}
#endif

/// Vertical center of the bubble the clock time lines up with. Speech wins over a card.
private struct AskTimeAnchor {
    var anchor: Anchor<CGRect>
    var priority: Int
}

/// On-screen frames of answer-card pagers. A time-reveal drag that starts inside one does not run.
private struct AskPagerFrameKey: PreferenceKey {
    static var defaultValue: [CGRect] { [] }

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct AskTimeAnchorKey: PreferenceKey {
    static var defaultValue: AskTimeAnchor? { nil }

    static func reduce(value: inout AskTimeAnchor?, nextValue: () -> AskTimeAnchor?) {
        guard let next = nextValue() else { return }
        if next.priority >= (value?.priority ?? -1) {
            value = next
        }
    }
}

private extension View {
    /// A second menu only when the answer has no speech bubble to hold the first one.
    @ViewBuilder
    func askBubbleMenu(
        text: String,
        fill: Color,
        foreground: Color,
        answer: AskAnswerMenu?,
        when enabled: Bool
    ) -> some View {
        if enabled {
            modifier(AskBubbleMenu(text: text, fill: fill, foreground: foreground, answer: answer))
        } else {
            self
        }
    }

    func askTimeAnchor(priority: Int) -> some View {
        anchorPreference(key: AskTimeAnchorKey.self, value: .bounds) { anchor in
            AskTimeAnchor(anchor: anchor, priority: priority)
        }
    }
}


#if DEBUG
/// Compact debug summary above an answer. Tap opens that turn's trace sheet.
private struct AskWorkedTracePill: View {
    let caption: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(caption)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AskPlatform.tertiaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityHint("Shows the debug trace for this answer")
    }
}
#endif

/// The thinking orb beside the live status. Working while choosing, searching while a tool runs, composing while writing.
private struct AskThinkingRow: View {
    let title: String
    let detail: String
    let phase: AskChatPhase

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ThinkingOrb(state: orbState, size: .px64, theme: .auto, displaySize: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                AskSkeletonText(text: title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? title : "\(title), \(detail)")
    }

    private var orbState: OrbState {
        switch phase {
        case .thinking, .choosing: .working
        case .tool: .searching
        case .writing: .composing
        }
    }
}

/// Working, then connecting, then searching. It stays on searching. Reduce Motion holds the first frame.
struct AskOrbSequence: View {
    var displaySize: Double
    var showsLabel: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    static let states: [OrbState] = [.working, .connecting, .searching]
    private static let dwell: Duration = .milliseconds(2500)

    private var state: OrbState { Self.states[index] }

    var body: some View {
        Group {
            if showsLabel {
                HStack(spacing: 16) {
                    orb
                    Text(state.styleTitle)
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                }
            } else {
                orb
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: index)
        .task(id: reduceMotion) {
            index = 0
            guard !reduceMotion else { return }
            for next in Self.states.indices.dropFirst() {
                try? await Task.sleep(for: Self.dwell)
                guard !Task.isCancelled else { return }
                index = next
            }
        }
    }

    private var orb: some View {
        ThinkingOrb(state: state, size: .px64, theme: .auto, displaySize: displaySize)
            .accessibilityHidden(true)
    }
}

extension OrbState {
    var styleTitle: String {
        switch self {
        case .working: "Working"
        case .searching: "Searching"
        case .solving: "Solving"
        case .listening: "Listening"
        case .connecting: "Connecting"
        case .weaving: "Weaving"
        case .composing: "Composing"
        case .breathing: "Breathing"
        case .shaping: "Shaping"
        }
    }
}

/// Status line with a highlight that sweeps across the words. Reduce Motion holds it still.
private struct AskSkeletonText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(reduceMotion ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: text)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.9), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.55)
                        .offset(x: phase * proxy.size.width)
                    }
                    .mask {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.35
                }
            }
    }
}

/// Symbol, title, and description centered while the thread has no turns.
private struct AskEmptyPrompt: View {
    let appearance: AskChatAppearance
    let fallbackTitle: String

    private var mark: AskChatLogo {
        appearance.emptyLogo ?? appearance.logo
    }

    private var heading: String {
        let custom = appearance.emptyTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? fallbackTitle : custom
    }

    var body: some View {
        VStack(spacing: 12) {
            emptyMark
                .foregroundStyle(appearance.tint)
            Text(heading)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(appearance.emptyMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyMark: some View {
        switch mark {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 40, weight: .semibold))
                .accessibilityHidden(true)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
        case .none:
            Image(systemName: appearance.composerSymbol)
                .font(.system(size: 40, weight: .semibold))
                .accessibilityHidden(true)
        }
    }
}

/// The down button shows when the thread is taller than the screen and its top is on screen.
enum AskScrollEdge {
    /// Extra height, past the screen, before the thread counts as longer than the view.
    static let overflow: CGFloat = 80
    /// How close the visible top must be to the start of the thread.
    static let topSlop: CGFloat = 24

    static func showsJumpToBottom(
        contentHeight: CGFloat,
        containerHeight: CGFloat,
        visibleMinY: CGFloat
    ) -> Bool {
        contentHeight > containerHeight + overflow && visibleMinY <= topSlop
    }
}

#if os(iOS) || os(visionOS)
/// The composer lives in a bottom safe-area bar, outside this scroll view, so a drag or tap ends editing on the window.
private struct AskChatScrollKeyboardDismiss: UIViewRepresentable {
    func makeUIView(context: Context) -> AskChatScrollKeyboardDismissView {
        AskChatScrollKeyboardDismissView()
    }

    func updateUIView(_ uiView: AskChatScrollKeyboardDismissView, context: Context) {
        uiView.attachIfNeeded()
    }
}

private final class AskChatScrollKeyboardDismissView: UIView {
    private weak var scroll: UIScrollView?
    private var tap: UITapGestureRecognizer?
    private var hooked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detach()
        } else {
            attachIfNeeded()
        }
    }

    fileprivate func attachIfNeeded() {
        guard !hooked, window != nil, let scroll = enclosingScrollView() else { return }
        hooked = true
        self.scroll = scroll
        scroll.panGestureRecognizer.addTarget(self, action: #selector(scrolled(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        scroll.addGestureRecognizer(tap)
        self.tap = tap
    }

    private func enclosingScrollView() -> UIScrollView? {
        var node = superview
        while let current = node {
            if let scroll = current as? UIScrollView { return scroll }
            node = current.superview
        }
        return nil
    }

    @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        gesture.view?.window?.endEditing(true)
    }

    @objc private func tapped() {
        window?.endEditing(true)
    }

    private func detach() {
        scroll?.panGestureRecognizer.removeTarget(self, action: #selector(scrolled(_:)))
        if let tap {
            scroll?.removeGestureRecognizer(tap)
            self.tap = nil
        }
        scroll = nil
        hooked = false
    }
}
#endif

#endif
