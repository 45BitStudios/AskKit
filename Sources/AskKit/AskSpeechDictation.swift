import AVFoundation
#if os(iOS) || os(macOS) || os(visionOS)
import Speech
#endif
import os

/// Silence after the last new word. Matches the travel-mode listen clock: unchanged text for 2.5 seconds commits.
struct AskListenClock: Equatable {
    static let silence: TimeInterval = 2.5

    private(set) var latest = ""
    private(set) var deadline: Date?
    private var committed = false
    private var cancelled = false

    /// True when this partial moved the silence deadline. The same words do not reset it.
    mutating func note(_ text: String, now: Date) -> Bool {
        guard !committed, !cancelled else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != latest else { return false }
        latest = trimmed
        deadline = now.addingTimeInterval(Self.silence)
        return true
    }

    /// The utterance once the silence interval has elapsed. Empty text never commits.
    mutating func commitIfDue(now: Date) -> String? {
        guard !committed, !cancelled, let deadline, now >= deadline else { return nil }
        return finish()
    }

    /// Seconds until silence commits. Nil once the words are committed, cancelled, or still empty.
    func timeUntilCommit(now: Date) -> TimeInterval? {
        guard !committed, !cancelled, let deadline else { return nil }
        return deadline.timeIntervalSince(now)
    }

    /// A final result, a recognition error that already has words, or the listen cap.
    mutating func commitNow() -> String? {
        guard !committed, !cancelled else { return nil }
        return finish()
    }

    mutating func cancel() {
        cancelled = true
        deadline = nil
    }

    private mutating func finish() -> String? {
        let utterance = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return nil }
        committed = true
        deadline = nil
        return utterance
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
/// Fills a composer while the person speaks. Stop keeps the text and does not send it.
/// `listen` is the other path: a pause commits the words so the chat can answer and speak.
@MainActor
@Observable
package final class AskSpeechDictation {
    package private(set) var isRecording = false
    /// True while a pause will send the words. Dictation leaves this false.
    package private(set) var isListening = false

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    /// Written on the audio tap and read by the composer glow. Not observed, so a buffer does not redraw the chat.
    nonisolated private let meter = AskVoiceMeter()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var transcript = AskDictationTranscript()
    private var published = ""
    private var timeout: DispatchWorkItem?
    private var onPartial: (String) -> Void = { _ in }
    private var onUtterance: (String) -> Void = { _ in }
    private var onUnavailable: (String) -> Void = { _ in }
    private var capture = Capture.dictate
    private var clock = AskListenClock()
    private var silence: DispatchWorkItem?
    private var hasTap = false
    private var lastRestart = Date.distantPast
    private let requestLock = OSAllocatedUnfairLock<SpeechRequest?>(initialState: nil)
    private let session = AskDictationSession.shared

    package init() {}

    package func start(
        startingWith existing: String = "",
        onPartial: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) async {
        stop()
        guard await Self.authorized() else {
            onUnavailable("Turn on microphone and speech recognition to ask by voice.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            onUnavailable("Speech recognition isn’t available right now.")
            return
        }
        self.onPartial = onPartial
        self.onUnavailable = onUnavailable
        transcript = AskDictationTranscript(committed: existing)
        published = transcript.text
        isRecording = true
        AskCue.prepareTap()
        AskCue.recordingStarted()
        do {
            try await session.activate()
            try installTap()
            beginRecognition(recognizer)
            engine.prepare()
            try engine.start()
        } catch {
            stop(playCue: false)
            onUnavailable("Couldn’t start the microphone.")
            return
        }
        armTimeout()
    }

    /// Listens until the words stop changing, then returns them. Stop before that keeps nothing.
    package func listen(
        onPartial: @escaping (String) -> Void,
        onUtterance: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) async {
        stop()
        guard await Self.authorized() else {
            onUnavailable("Turn on microphone and speech recognition to ask by voice.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            onUnavailable("Speech recognition isn’t available right now.")
            return
        }
        self.onPartial = onPartial
        self.onUtterance = onUtterance
        self.onUnavailable = onUnavailable
        clock = AskListenClock()
        capture = .listen
        isListening = true
        transcript = AskDictationTranscript()
        published = ""
        isRecording = true
        AskCue.prepareTap()
        AskCue.recordingStarted()
        do {
            try await session.activate()
            try installTap()
            beginRecognition(recognizer)
            engine.prepare()
            try engine.start()
        } catch {
            stop(playCue: false)
            onUnavailable("Couldn’t start the microphone.")
            return
        }
        armTimeout()
    }

    private func armTimeout() {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.capture == .listen, let utterance = self.clock.commitNow() {
                self.deliverListen(utterance)
            } else {
                self.stop(playCue: false)
            }
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: timeout)
    }

    /// Smoothed loudness from 0 to 1. The closure only reads the audio-tap lock.
    package nonisolated func levelSource() -> @Sendable () -> Double {
        let meter = meter
        return { meter.read() }
    }

    package func stop() {
        stop(playCue: isRecording)
    }

    package func stop(playCue: Bool) {
        guard isRecording || task != nil || engine.isRunning else { return }
        meter.reset()
        isRecording = false
        isListening = false
        capture = .dictate
        clock.cancel()
        silence?.cancel()
        silence = nil
        generation += 1
        transcript = AskDictationTranscript()
        published = ""
        onPartial = { _ in }
        onUtterance = { _ in }
        timeout?.cancel()
        timeout = nil
        task?.cancel()
        task = nil
        removeTapIfNeeded()
        let pending = requestLock.withLock { current -> SpeechRequest? in
            let old = current
            current = nil
            return old
        }
        pending?.request.endAudio()
        engine.stop()
        if playCue {
            AskCue.tap()
        }
        session.deactivate {
            guard playCue else { return }
            Task { @MainActor in
                AskCue.recordingStopped()
            }
        }
    }

    /// Plays the send haptic and click once the recording session has released audio.
    /// A click played while that session is still up is silent.
    package func playSendCue() {
        session.afterIdle {
            Task { @MainActor in
                AskCue.tap()
                AskCue.sent()
            }
        }
    }

    /// One tap for the whole recording. Reinstalling it on each final result drops buffers
    /// (`cannot add handler to 0 from 0`) because the input format is 0 during the swap.
    private func installTap() throws {
        let node = engine.inputNode
        removeTapIfNeeded()
        let output = node.outputFormat(forBus: 0)
        let input = node.inputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0,
              input.sampleRate > 0, input.channelCount > 0,
              input.sampleRate == output.sampleRate else {
            throw DictationError.unavailable
        }
        let frames = AVAudioFrameCount(max(output.sampleRate * 0.1, 1024))
        let meter = meter
        let requestLock = requestLock
        try node.installAudioTap(onBus: 0, bufferSize: frames, format: output) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            meter.push(AskVoiceLevel.normalized(buffer))
            let box = requestLock.withLock { $0 }
            box?.append(AVAudioPCMBuffer(copying: buffer))
        }
        hasTap = true
    }

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) {
        generation += 1
        let generation = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        task?.cancel()
        let box = SpeechRequest(request)
        let previous = requestLock.withLock { current -> SpeechRequest? in
            let old = current
            current = box
            return old
        }
        previous?.request.endAudio()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, generation == self.generation, self.isRecording else { return }
                let shown = self.transcript.update(hypothesis: text, isFinal: isFinal && !failed)
                if shown != self.published {
                    self.published = shown
                    self.onPartial(shown)
                }
                if self.capture == .listen {
                    self.hear(shown, isFinal: isFinal && !failed, failed: failed)
                    return
                }
                if failed {
                    if shown.isEmpty {
                        self.fail("Couldn’t start the microphone.")
                    } else {
                        self.stop(playCue: false)
                    }
                } else if isFinal {
                    if text.isEmpty, Date().timeIntervalSince(self.lastRestart) < 0.4 {
                        self.stop(playCue: false)
                        return
                    }
                    self.lastRestart = Date()
                    self.beginRecognition(recognizer)
                }
            }
        }
    }

    private func hear(_ shown: String, isFinal: Bool, failed: Bool) {
        if clock.note(shown, now: Date()) {
            scheduleSilence()
        }
        guard failed || isFinal else { return }
        if let utterance = clock.commitNow() {
            deliverListen(utterance)
        } else if failed {
            fail("Couldn’t start the microphone.")
        } else {
            stop(playCue: false)
        }
    }

    private func scheduleSilence() {
        armSilence(after: AskListenClock.silence)
    }

    /// Fires on the silence interval. An early timer waits out the remaining time instead of dropping the words.
    private func armSilence(after delay: TimeInterval) {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.capture == .listen else { return }
            let now = Date()
            if let utterance = self.clock.commitIfDue(now: now) {
                self.deliverListen(utterance)
                return
            }
            guard let remaining = self.clock.timeUntilCommit(now: now), remaining > 0 else { return }
            self.armSilence(after: remaining)
        }
        silence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func deliverListen(_ utterance: String) {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliver = onUtterance
        stop(playCue: false)
        guard !trimmed.isEmpty else { return }
        let delivery = ListenDelivery(text: trimmed, deliver: deliver)
        session.afterIdle {
            Task { @MainActor in
                delivery.fire()
            }
        }
    }

    private func fail(_ message: String) {
        let report = onUnavailable
        stop(playCue: false)
        report(message)
    }

    /// `removeTap` raises when the bus has no tap.
    private func removeTapIfNeeded() {
        guard hasTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        hasTap = false
    }

    /// Permission callbacks arrive off the main actor. Keeping this off the main actor avoids the isolation trap.
    nonisolated private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private enum DictationError: Error {
    case unavailable
}

private enum Capture {
    case dictate
    case listen
}

/// Holds the voice callback across the audio-session queue. Fired once, back on the main actor.
private final class ListenDelivery: @unchecked Sendable {
    private let text: String
    private let deliver: (String) -> Void

    init(text: String, deliver: @escaping (String) -> Void) {
        self.text = text
        self.deliver = deliver
    }

    func fire() {
        deliver(text)
    }
}
#else
/// Apple TV and Apple Watch have no speech recognizer. The mic says so and records nothing.
@MainActor
@Observable
package final class AskSpeechDictation {
    package private(set) var isRecording = false
    package private(set) var isListening = false

    static let unavailable = "Speech recognition isn't available on this device."

    package init() {}

    package func start(
        startingWith existing: String = "",
        onPartial: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) async {
        onUnavailable(Self.unavailable)
    }

    package func listen(
        onPartial: @escaping (String) -> Void,
        onUtterance: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) async {
        onUnavailable(Self.unavailable)
    }

    package nonisolated func levelSource() -> @Sendable () -> Double {
        { 0 }
    }

    package func stop() {}

    package func stop(playCue: Bool) {}

    package func playSendCue() {
        AskCue.tap()
        AskCue.sent()
    }
}
#endif

/// Words already accepted, plus the phrase the recognizer is still hearing.
/// A pause starts a new phrase. That phrase is appended. It does not replace the field.
struct AskDictationTranscript: Equatable {
    private(set) var committed: String
    private(set) var segment: String

    init(committed: String = "") {
        self.committed = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        self.segment = ""
    }

    var text: String { Self.join(committed, segment) }

    mutating func update(hypothesis: String, isFinal: Bool) -> String {
        let spoken = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            let phrase = spoken.isEmpty ? segment : spoken
            if !phrase.isEmpty {
                if Self.extends(text, with: phrase) {
                    committed = phrase
                } else if Self.words(phrase) == Self.words(segment) {
                    committed = Self.join(committed, segment)
                } else {
                    committed = Self.join(committed, phrase)
                }
            }
            segment = ""
            return committed
        }
        guard !spoken.isEmpty else { return text }
        if Self.extends(text, with: spoken) {
            committed = ""
            segment = spoken
            return segment
        }
        switch Self.relation(of: spoken, to: segment) {
        case .replace:
            segment = spoken
        case .keep:
            break
        case .append:
            committed = Self.join(committed, segment)
            segment = spoken
        }
        return text
    }

    private static func join(_ leading: String, _ trailing: String) -> String {
        let head = leading.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = trailing.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return "\(head) \(tail)"
    }

    private enum Change {
        case replace
        case keep
        case append
    }

    /// Growth and a one-word correction stay in the current phrase. Anything else is a new phrase.
    private static func relation(of next: String, to previous: String) -> Change {
        let old = words(previous)
        let new = words(next)
        if old.isEmpty { return .replace }
        if new.count >= old.count, Array(new.prefix(old.count)) == old { return .replace }
        if new.count < old.count, Array(old.prefix(new.count)) == new { return .keep }
        let overlap = zip(old, new).prefix { $0.0 == $0.1 }.count
        if overlap > 0, overlap >= old.count - 1, abs(new.count - old.count) <= 1 { return .replace }
        return .append
    }

    private static func extends(_ existing: String, with next: String) -> Bool {
        let old = words(existing)
        let new = words(next)
        guard !old.isEmpty, new.count >= old.count else { return false }
        return Array(new.prefix(old.count)) == old
    }

    private static func words(_ text: String) -> [String] {
        text.split { $0.isWhitespace }.compactMap { token in
            let word = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            return word.isEmpty ? nil : word
        }
    }
}

/// Serializes session changes off the main thread. `setActive` on the main thread logs
/// AVAudioSession_iOS.mm:978 and can stall the UI. iOS 27's activate and deactivate return immediately.
final class AskDictationSession: @unchecked Sendable {
    static let shared = AskDictationSession()

    private let lock = NSLock()
    private var running = false
    private var waiters: [() -> Void] = []

    func activate() async throws {
#if os(macOS) || os(tvOS) || os(watchOS)
        // The Mac has no shared audio session, and Apple TV and Apple Watch never record.
        // Speech plays on the app's default session there.
        return
#else
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            run {
                DispatchQueue.global(qos: .userInitiated).async {
                    let session = AVAudioSession.sharedInstance()
                    do {
                        try session.setCategory(
                            .playAndRecord,
                            mode: .measurement,
                            options: [.defaultToSpeaker, .duckOthers]
                        )
                        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                        try session.overrideOutputAudioPort(.speaker)
                    } catch {
                        continuation.resume(throwing: error)
                        self.finish()
                        return
                    }
                    session.activate(options: []) { activated, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if !activated {
                            continuation.resume(throwing: DictationError.unavailable)
                        } else {
                            continuation.resume()
                        }
                        self.finish()
                    }
                }
            }
        }
#endif
    }

    /// Speaker route for a spoken answer. Listening must already be stopped.
    func activateSpoken() async throws {
#if os(macOS) || os(tvOS) || os(watchOS)
        // The Mac has no shared audio session, and Apple TV and Apple Watch never record.
        // Speech plays on the app's default session there.
        return
#else
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            run {
                DispatchQueue.global(qos: .userInitiated).async {
                    let session = AVAudioSession.sharedInstance()
                    do {
                        try session.setCategory(
                            .playAndRecord,
                            mode: .spokenAudio,
                            options: [.defaultToSpeaker, .duckOthers]
                        )
                        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                        try session.overrideOutputAudioPort(.speaker)
                    } catch {
                        continuation.resume(throwing: error)
                        self.finish()
                        return
                    }
                    session.activate(options: []) { activated, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if !activated {
                            continuation.resume(throwing: DictationError.unavailable)
                        } else {
                            continuation.resume()
                        }
                        self.finish()
                    }
                }
            }
        }
#endif
    }

    /// Releases the recording session, then restores a category that can play system sounds.
    /// `.measurement` swallows those sounds until the category changes back.
    func deactivate(then completion: (@Sendable () -> Void)? = nil) {
#if os(macOS) || os(tvOS) || os(watchOS)
        completion?()
#else
        run {
            let session = AVAudioSession.sharedInstance()
            session.deactivate(options: .notifyOthersOnDeactivation) { _, _ in
                try? session.setAllowHapticsAndSystemSoundsDuringRecording(false)
                try? session.setCategory(.ambient, mode: .default)
                self.finish()
                completion?()
            }
        }
#endif
    }

    /// Runs after any activate or deactivate already in flight.
    func afterIdle(_ completion: @escaping @Sendable () -> Void) {
        run {
            self.finish()
            completion()
        }
    }

    private func run(_ work: @escaping () -> Void) {
        lock.lock()
        if running {
            waiters.append(work)
            lock.unlock()
        } else {
            running = true
            lock.unlock()
            work()
        }
    }

    private func finish() {
        lock.lock()
        let next = waiters.isEmpty ? nil : waiters.removeFirst()
        if next == nil {
            running = false
        }
        lock.unlock()
        next?()
    }
}

/// Root-mean-square loudness for the composer glow. Quiet speech still moves the beam.
enum AskVoiceLevel {
    static func normalized(samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return unit(rms: (sum / Float(samples.count)).squareRoot())
    }

    static func normalized(_ buffer: AVReadOnlyAudioPCMBuffer) -> Double {
        let frames = buffer.frameLength
        guard frames > 0, buffer.format.channelCount > 0 else { return 0 }
        let step = max(buffer.stride, 1)
        switch buffer.channelData(0) {
        case .float(let samples):
            return unit(rms: rms(frames: frames, step: step, count: samples.count) { samples[$0] })
        case .int16(let samples):
            let scale = 1 / Float(Int16.max)
            return unit(rms: rms(frames: frames, step: step, count: samples.count) { Float(samples[$0]) * scale })
        case .int32(let samples):
            let scale = 1 / Float(Int32.max)
            return unit(rms: rms(frames: frames, step: step, count: samples.count) { Float(samples[$0]) * scale })
        @unknown default:
            return 0
        }
    }

    private static func rms(frames: Int, step: Int, count: Int, sample: (Int) -> Float) -> Float {
        var sum: Float = 0
        var seen = 0
        var index = 0
        while seen < frames, index < count {
            let value = sample(index)
            sum += value * value
            seen += 1
            index += step
        }
        guard seen > 0 else { return 0 }
        return (sum / Float(seen)).squareRoot()
    }

    /// Fast attack and a slower release, so the beam rises with a word and eases off after it.
    static func smooth(previous: Double, sample: Double) -> Double {
        let rate = sample >= previous ? 0.55 : 0.22
        return previous + (sample - previous) * rate
    }

    private static func unit(rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, Double(rms) * 14).squareRoot()
    }
}

/// The audio tap writes this. The glow samples it. A buffer never publishes through `@Observable`.
final class AskVoiceMeter: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0.0)

    func push(_ sample: Double) {
        let clamped = min(1, max(0, sample))
        lock.withLock { level in
            level = AskVoiceLevel.smooth(previous: level, sample: clamped)
        }
    }

    func read() -> Double {
        lock.withLock { $0 }
    }

    func reset() {
        lock.withLock { $0 = 0 }
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
private final class SpeechRequest: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}
#endif
