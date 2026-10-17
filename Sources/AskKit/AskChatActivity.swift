import SwiftUI

/// What the thinking orb is showing while a turn runs.
public enum AskChatPhase: Sendable {
    /// The turn has started and no profile has spoken yet.
    case thinking
    /// Choosing a skill, or a specialist is active before its tool runs.
    case choosing
    /// A specialist tool is running.
    case tool
    /// The writer is producing the answer.
    case writing
}

/// Status line beside the thinking orb. A skill can call `update` while its turn is running.
public enum AskChatActivity {
    @MainActor
    public static func update(_ title: String) {
        show(title)
    }

    @MainActor
    static func show(_ title: String, detail: String = "", phase: AskChatPhase = .thinking) {
        let center = AskChatActivityCenter.shared
        center.title = title
        center.detail = detail
        center.phase = phase
    }

    /// The reply text as the model writes it. Cleared when the turn is stored,
    /// and cleared early when the preview can no longer be the stored line.
    @MainActor
    public static func stream(_ text: String) {
        AskChatActivityCenter.shared.partial = text
        AskCue.streamAdvanced(to: text)
    }

    @MainActor
    public static func clearStream() {
        AskChatActivityCenter.shared.partial = ""
        AskCue.streamEnded()
    }
}

/// Whether answer text grows in the bubble while the model writes.
/// Off keeps the thinking row until the turn stores the line.
/// The key is `AskKit.stream` in standard `UserDefaults`. A missing key is off.
public enum AskStreamSelection: Sendable {
    public static let storageKey = "AskKit.stream"

    public static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

/// Whether assistant bubbles render Markdown through Textual and the writer may use rich formatting.
/// Off keeps plain text and the short plain reply instructions.
/// The key is `AskKit.markdown` in standard `UserDefaults`. A missing key is off.
public enum AskMarkdownSelection: Sendable {
    public static let storageKey = "AskKit.markdown"

    public static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

/// Whether debug builds show a "Worked … · N step" pill above each answer.
/// Tap opens that turn's trace. The key is `AskKit.workedTrace` in standard `UserDefaults`.
/// A missing key is on.
public enum AskWorkedTraceSelection: Sendable {
    public static let storageKey = "AskKit.workedTrace"

    public static var isOn: Bool {
        get {
            guard UserDefaults.standard.object(forKey: storageKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: storageKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

/// Shows a rewrite only while it can still be the stored line.
/// An empty snapshot leaves the current preview in place.
/// In plain mode a second paragraph is ignored, so a background dump cannot replace a short line.
/// A partial over ``AskReplyBudget``'s character limit, or one that adds an equals sign in plain mode, is taken down.
/// A reply that must call a tool stays off the bubble until the turn stores the line.
/// Streaming off keeps every snapshot off the bubble.
/// Otherwise a discarded draft appears, clears, and the next specialist starts over.
@MainActor
enum AskReplyPreview {
    static func note(_ text: String, facts: String, holdsUntilTool: Bool = false) {
        guard AskStreamSelection.isOn else { return }
        guard !holdsUntilTool else { return }
        let partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        let rich = AskMarkdownSelection.isOn
        // Plain snapshots are the text so far. Once a blank line appears, every later
        // snapshot includes it, and the first paragraph stays on screen.
        // Rich Markdown needs blank lines between blocks, so those drafts still stream.
        if !rich, partial.range(of: #"\n[ \t]*\n"#, options: .regularExpression) != nil {
            return
        }
        guard AskGuide.acceptsReply(partial, facts: facts, rich: rich) else {
            AskChatActivity.clearStream()
            return
        }
        AskChatActivity.stream(partial)
    }
}

@MainActor
@Observable
package final class AskChatActivityCenter {
    package static let shared = AskChatActivityCenter()
    package var title = ""
    package var detail = ""
    package var phase = AskChatPhase.thinking
    package var partial = ""
}
