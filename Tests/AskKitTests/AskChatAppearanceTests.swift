import SwiftUI
import UIKit
import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskChatAppearanceTests: XCTestCase {
    func testDefaultTintStaysTheHostAccent() {
        let appearance = AskChatAppearance()
        XCTAssertEqual(appearance.tint, Color.accentColor)
        XCTAssertEqual(appearance.accent, Color.accentColor)
        XCTAssertEqual(appearance.accentText, Color.accentColor)
        XCTAssertNil(appearance.cardFill)
    }

    func testAccentTextDefaultsToTheAccent() {
        let appearance = AskChatAppearance(accent: .orange)
        XCTAssertEqual(appearance.accent, .orange)
        XCTAssertEqual(appearance.accentText, .orange)
        let custom = AskChatAppearance(accent: .orange, accentText: .blue)
        XCTAssertEqual(custom.accentText, .blue)
    }

    func testUserForegroundPicksBlackOnALightTint() {
        let appearance = AskChatAppearance(tint: Color(red: 176.0 / 255.0, green: 112.0 / 255.0, blue: 1))
        XCTAssertLessThan(brightness(of: appearance.userForeground), 0.15)
    }

    func testUserForegroundPicksWhiteOnADarkTint() {
        let appearance = AskChatAppearance(tint: Color(red: 0.10, green: 0.12, blue: 0.28))
        XCTAssertGreaterThan(brightness(of: appearance.userForeground), 0.9)
    }

    func testHostCanPassTheLabelColorBesideTheTint() {
        let appearance = AskChatAppearance(tint: .yellow, userForeground: .blue)
        XCTAssertEqual(appearance.userForeground, .blue)
    }

    func testUserBubbleDefaultsToTheTint() {
        let appearance = AskChatAppearance(tint: .red)
        XCTAssertEqual(appearance.userBubble, .red)
        XCTAssertEqual(appearance.thinkingTitle, "Thinking")
        XCTAssertEqual(appearance.emptyMessage, "Ask a question, or start with a suggestion.")
        XCTAssertNil(appearance.emptyTitle)
        XCTAssertTrue(appearance.showsMicrophone)
        XCTAssertTrue(appearance.voiceColors.isEmpty)
    }

    func testDarkChipLabelLiftsADimTint() {
        let tint = Color(red: 0.22, green: 0.28, blue: 0.62)
        let lifted = AskTintChrome.label(tint, scheme: .dark)
        XCTAssertGreaterThan(brightness(of: lifted), 0.75)
        XCTAssertEqual(brightness(of: AskTintChrome.label(tint, scheme: .light)), brightness(of: tint), accuracy: 0.001)
    }

    func testBeamShiftParksOceanOnTheTintHue() {
        let tint = Color(red: 0.72, green: 0.32, blue: 0.12)
        let shift = AskBeamTint.shift(tint: tint, override: [])
        var landed = AskBeamTint.oceanCenter + shift
        landed.formTruncatingRemainder(dividingBy: 360)
        if landed < 0 { landed += 360 }
        let target = hue(of: tint) * 360
        let delta = abs(landed - Double(target))
        XCTAssertLessThan(min(delta, 360 - delta), 12)
    }

    func testVoicePaletteStaysInTheTintFamily() {
        let tint = Color(red: 0.72, green: 0.32, blue: 0.12)
        let colors = AskVoicePalette.colors(tint: tint, override: [])
        XCTAssertEqual(colors.count, 7)
        let tintHue = hue(of: tint)
        for color in colors {
            XCTAssertLessThan(hueDistance(hue(of: color), tintHue), 0.12)
        }
    }

    func testVoicePaletteUsesPassedColors() {
        let colors = AskVoicePalette.colors(tint: .orange, override: [.blue, .green])
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(colors[0], .blue)
        XCTAssertEqual(colors[1], .green)
    }

    func testVoicePaletteSuppliesBackdropColorsWhenOverrideIsEmpty() {
        let tint = Color(red: 0.05, green: 0.45, blue: 0.32)
        let colors = AskVoicePalette.colors(tint: tint, override: [])
        XCTAssertEqual(colors.count, 7)
        XCTAssertGreaterThan(colors.count, 5)
    }

    private func brightness(of color: Color) -> CGFloat {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        _ = UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return brightness
    }

    private func hue(of color: Color) -> CGFloat {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        _ = UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return hue
    }

    private func hueDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let raw = abs(lhs - rhs)
        return min(raw, 1 - raw)
    }

    @MainActor
    func testActivityUpdateChangesTheSkeletonStatus() {
        AskChatActivity.update("Searching")
        XCTAssertEqual(AskChatActivityCenter.shared.title, "Searching")
    }

    @MainActor
    func testStreamedReplyClears() {
        AskChatActivity.stream("The stove is free")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "The stove is free")
        AskChatActivity.clearStream()
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
    }

    @MainActor
    func testLongRewritePreviewIsTakenDown() {
        AskStreamSelection.isOn = true
        AskChatActivity.clearStream()
        AskReplyPreview.note("Sam is expected at 2 p.m.", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "Sam is expected at 2 p.m.")
        AskReplyPreview.note(String(repeating: "a", count: 601), facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
    }

    @MainActor
    func testEqualsRewritePreviewIsNotShown() {
        AskStreamSelection.isOn = true
        AskChatActivity.stream("Sam is expected at 2 p.m.")
        AskReplyPreview.note("visitor=Sam", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
    }

    @MainActor
    func testEmptyRewriteSnapshotLeavesThePreview() {
        AskStreamSelection.isOn = true
        AskChatActivity.clearStream()
        AskReplyPreview.note("Sam is expected at 2 p.m.", facts: "Sam at 2 p.m.")
        AskReplyPreview.note("   ", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "Sam is expected at 2 p.m.")
    }

    @MainActor
    func testBackgroundDumpDoesNotReplaceTheShortLine() {
        AskStreamSelection.isOn = true
        AskChatActivity.clearStream()
        let facts = "The next visitor is Sam at 2 p.m., here to see Jordan."
        let sentence = "The next person coming is Sam at 2 p.m. to see Jordan."
        AskReplyPreview.note(sentence, facts: facts)
        AskReplyPreview.note(sentence + "\n\nBackground\nThe desk opens at 8 a.m.", facts: facts)
        XCTAssertEqual(AskChatActivityCenter.shared.partial, sentence)
    }

    func testJumpToBottomShowsAtTheTopOfALongThread() {
        XCTAssertTrue(AskScrollEdge.showsJumpToBottom(contentHeight: 1600, containerHeight: 700, visibleMinY: 0))
        XCTAssertTrue(AskScrollEdge.showsJumpToBottom(contentHeight: 1600, containerHeight: 700, visibleMinY: 20))
        XCTAssertFalse(AskScrollEdge.showsJumpToBottom(contentHeight: 1600, containerHeight: 700, visibleMinY: 400))
        XCTAssertFalse(AskScrollEdge.showsJumpToBottom(contentHeight: 720, containerHeight: 700, visibleMinY: 0))
    }

    @MainActor
    func testAToolRequiredDraftStaysOffTheBubble() {
        AskStreamSelection.isOn = true
        AskChatActivity.clearStream()
        AskReplyPreview.note(
            "You are at Your Lake, Isabella. Austin is in Austin, TX.",
            facts: "Only a tool result may be stated.",
            holdsUntilTool: true
        )
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
        AskReplyPreview.note("Sam is expected at 2 p.m.", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "Sam is expected at 2 p.m.")
    }

    @MainActor
    func testWholeDumpInOneSnapshotIsNotShown() {
        AskStreamSelection.isOn = true
        AskChatActivity.clearStream()
        let dump = "The next person coming is Sam at 2 p.m. to see Jordan.\n\nBackground\n"
            + String(repeating: "The desk is open. ", count: 20)
        AskReplyPreview.note(dump, facts: "The next visitor is Sam at 2 p.m., here to see Jordan.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
    }

    @MainActor
    func testStreamingOffKeepsTheDraftOffTheBubble() {
        let previous = AskStreamSelection.isOn
        defer { AskStreamSelection.isOn = previous }
        AskStreamSelection.isOn = false
        AskChatActivity.clearStream()
        AskReplyPreview.note("Sam is expected at 2 p.m.", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "")
        AskStreamSelection.isOn = true
        AskReplyPreview.note("Sam is expected at 2 p.m.", facts: "Sam at 2 p.m.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, "Sam is expected at 2 p.m.")
    }

    @MainActor
    func testRichMarkdownPreviewKeepsBlankLines() {
        let previousStream = AskStreamSelection.isOn
        let previousMarkdown = AskMarkdownSelection.isOn
        defer {
            AskStreamSelection.isOn = previousStream
            AskMarkdownSelection.isOn = previousMarkdown
        }
        AskStreamSelection.isOn = true
        AskMarkdownSelection.isOn = true
        AskChatActivity.clearStream()
        let list = "Open items:\n\n- Milk\n- Eggs"
        AskReplyPreview.note(list, facts: "Milk and eggs are open.")
        XCTAssertEqual(AskChatActivityCenter.shared.partial, list)
    }

    func testWorkedTraceDefaultsOnAndRemembersOff() {
        let previous = UserDefaults.standard.object(forKey: AskWorkedTraceSelection.storageKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AskWorkedTraceSelection.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AskWorkedTraceSelection.storageKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: AskWorkedTraceSelection.storageKey)
        XCTAssertTrue(AskWorkedTraceSelection.isOn)
        AskWorkedTraceSelection.isOn = false
        XCTAssertFalse(AskWorkedTraceSelection.isOn)
        AskWorkedTraceSelection.isOn = true
        XCTAssertTrue(AskWorkedTraceSelection.isOn)
    }
}
