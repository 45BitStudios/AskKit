#if os(iOS)
import AudioToolbox
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
#endif

/// Button haptics and the record and send sounds.
/// iPhone plays both. watchOS and the Mac trackpad tap without sounds. tvOS and visionOS stay quiet.
@MainActor
package enum AskCue {
#if os(iOS)
    /// Kept alive so the tap is not dropped when the generator is released on the same line.
    private static let tapGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()
    private static let streamGenerator = UIImpactFeedbackGenerator(style: .soft)
#endif
    private static var streamedWords = 0

    static func prepareTap() {
#if os(iOS)
        tapGenerator.prepare()
#endif
    }

    package static func tap() {
#if os(iOS)
        tapGenerator.impactOccurred()
        tapGenerator.prepare()
#elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
#elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
#endif
    }

    /// One soft tap when the streamed reply gains a word.
    static func streamAdvanced(to text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > streamedWords else { return }
#if os(iOS)
        if streamedWords == 0 {
            streamGenerator.prepare()
        }
        streamGenerator.impactOccurred(intensity: 0.45)
        streamGenerator.prepare()
#endif
        streamedWords = words
    }

    static func streamEnded() {
        streamedWords = 0
    }

    /// `begin_record`. Played before the recording session takes the audio session.
    static func recordingStarted() {
#if os(iOS)
        AudioServicesPlaySystemSound(1113)
#endif
    }

    /// `end_record`. Played after the recording session has released the audio session.
    static func recordingStopped() {
#if os(iOS)
        AudioServicesPlaySystemSound(1114)
#endif
    }

    /// Light tap plus the end-recording sound. Used when a thinking request is stopped.
    package static func requestStopped() {
        tap()
        recordingStopped()
    }

    /// `key_press_click`. A short click. The mail-sent whoosh (1001) sounds like an airplane.
    static func sent() {
#if os(iOS)
        AudioServicesPlaySystemSound(1104)
#endif
    }
}
