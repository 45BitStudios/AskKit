import Testing
@testable import AskKit

@Suite("Host tint contrast and card radii")
struct AskContrastTests {
    @Test func blackWinsOnALightTintWhereWhiteFails() {
        // About 3.2:1 for white. A light host tint must not keep a white label.
        let light = AskSRGB(red: 176.0 / 255.0, green: 112.0 / 255.0, blue: 1)
        let white = AskSRGB.white.contrast(against: light)
        let black = AskSRGB.black.contrast(against: light)
        #expect(white > 3.0)
        #expect(white < 3.4)
        #expect(white < AskContrast.minimumTextRatio)
        #expect(black >= AskContrast.minimumTextRatio)
        #expect(AskContrast.label(on: light) == .black)
        #expect(AskContrast.label(on: light).color.contrast(against: light) >= AskContrast.minimumTextRatio)
    }

    @Test func whiteWinsOnADarkTint() {
        let dark = AskSRGB(red: 0.10, green: 0.12, blue: 0.28)
        #expect(AskContrast.label(on: dark) == .white)
        #expect(AskSRGB.white.contrast(against: dark) >= AskContrast.minimumTextRatio)
        #expect(AskSRGB.black.contrast(against: dark) < AskContrast.minimumTextRatio)
    }

    @Test func cardRadiiCollapseToFourSteps() {
        let steps = [AskCardRadius.small, AskCardRadius.medium, AskCardRadius.large, AskCardRadius.card]
        #expect(steps == [8, 12, 16, 22])
        #expect(Set(steps).count == 4)
    }
}
