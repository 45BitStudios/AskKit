import AVFoundation

/// The line Ask speaks after a voice turn. The stored spoken line, then the bubble text.
enum AskVoiceLine {
    static func text(from result: AskTurnResult) -> String {
        let spoken = result.pages.map(\.spoken).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !spoken.isEmpty { return spoken }
        let bubble = result.pages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !bubble.isEmpty { return bubble }
        switch result.fulfillment {
        case .reply(let reply):
            return reply.spoken.isEmpty ? reply.text : reply.spoken
        case .intent(let card):
            return card.spoken.isEmpty ? card.text : card.spoken
        }
    }
}

/// Speaks one answer through the shared audio session, then returns the session to ambient.
@MainActor
final class AskVoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AskVoiceSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    /// The utterance currently being spoken. Delegate callbacks for an older utterance are ignored.
    private var activeUtterance: AVSpeechUtterance?

    private override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.start(trimmed) {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.stop()
            }
        }
    }

    func stop() {
        interrupt()
        AskDictationSession.shared.deactivate()
    }

    /// Ends the current utterance without releasing the audio session. The next speak configures it.
    private func interrupt() {
        let done = onFinish
        onFinish = nil
        activeUtterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        done?()
    }

    private func start(_ text: String, done: @escaping () -> Void) {
        interrupt()
        onFinish = done
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(matching: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.15
        activeUtterance = utterance
        Task {
            do {
                try await AskDictationSession.shared.activateSpoken()
            } catch {
                self.complete(ObjectIdentifier(utterance))
                return
            }
            guard self.activeUtterance === utterance else {
                AskDictationSession.shared.deactivate()
                return
            }
            self.synthesizer.speak(utterance)
        }
    }

    /// Premium or enhanced voice for the device language, then the language default.
    private static func voice(matching language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.compare(language, options: .caseInsensitive) == .orderedSame
        }
        let ranked = voices.sorted { rank($0) > rank($1) }
        return ranked.first ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    private func complete(_ id: ObjectIdentifier) {
        guard let activeUtterance, ObjectIdentifier(activeUtterance) == id else { return }
        self.activeUtterance = nil
        let done = onFinish
        onFinish = nil
        done?()
        AskDictationSession.shared.deactivate()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.complete(id)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.complete(id)
        }
    }
}
