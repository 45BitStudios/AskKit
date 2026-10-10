import AVFoundation
import os
import Speech

/// Fills a composer while the person speaks. Stop keeps the text and does not send it.
@MainActor
@Observable
final class AskSpeechDictation {
    private(set) var isRecording = false

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
    private var onUnavailable: (String) -> Void = { _ in }
    private var hasTap = false
    private var lastRestart = Date.distantPast
    private let requestLock = OSAllocatedUnfairLock<SpeechRequest?>(initialState: nil)
    private let session = AskDictationSession()

    func start(
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
        let timeout = DispatchWorkItem { [weak self] in
            self?.stop(playCue: false)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: timeout)
    }

    /// Smoothed loudness from 0 to 1. The closure only reads the audio-tap lock.
    nonisolated func levelSource() -> @Sendable () -> Double {
        let meter = meter
        return { meter.read() }
    }

    func stop() {
        stop(playCue: isRecording)
    }

    private func stop(playCue: Bool) {
        guard isRecording || task != nil || engine.isRunning else { return }
        meter.reset()
        isRecording = false
        generation += 1
        transcript = AskDictationTranscript()
        published = ""
        onPartial = { _ in }
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
    func playSendCue() {
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
private final class AskDictationSession: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var waiters: [() -> Void] = []

    func activate() async throws {
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
    }

    /// Releases the recording session, then restores a category that can play system sounds.
    /// `.measurement` swallows those sounds until the category changes back.
    func deactivate(then completion: (@Sendable () -> Void)? = nil) {
        run {
            let session = AVAudioSession.sharedInstance()
            session.deactivate(options: .notifyOthersOnDeactivation) { _, _ in
                try? session.setAllowHapticsAndSystemSoundsDuringRecording(false)
                try? session.setCategory(.ambient, mode: .default)
                self.finish()
                completion?()
            }
        }
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

private final class SpeechRequest: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}
