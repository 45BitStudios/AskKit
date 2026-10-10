import AudioToolbox
import UIKit

/// Button haptics and the record and send sounds.
@MainActor
enum AskCue {
    /// Kept alive so the tap is not dropped when the generator is released on the same line.
    private static let tapGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()
    private static let streamGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static var streamedWords = 0

    static func prepareTap() {
        tapGenerator.prepare()
    }

    static func tap() {
        tapGenerator.impactOccurred()
        tapGenerator.prepare()
    }

    /// One soft tap when the streamed reply gains a word.
    static func streamAdvanced(to text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > streamedWords else { return }
        if streamedWords == 0 {
            streamGenerator.prepare()
        }
        streamedWords = words
        streamGenerator.impactOccurred(intensity: 0.45)
        streamGenerator.prepare()
    }

    static func streamEnded() {
        streamedWords = 0
    }

    /// `begin_record`. Played before the recording session takes the audio session.
    static func recordingStarted() {
        AudioServicesPlaySystemSound(1113)
    }

    /// `end_record`. Played after the recording session has released the audio session.
    static func recordingStopped() {
        AudioServicesPlaySystemSound(1114)
    }

    /// Light tap plus the end-recording sound. Used when a thinking request is stopped.
    static func requestStopped() {
        tap()
        recordingStopped()
    }

    /// `key_press_click`. A short click. The mail-sent whoosh (1001) sounds like an airplane.
    static func sent() {
        AudioServicesPlaySystemSound(1104)
    }
}
