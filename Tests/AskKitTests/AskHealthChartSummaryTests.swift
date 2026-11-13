import Testing
@testable import AskKit

@Suite("Health chart VoiceOver summary")
struct AskHealthChartSummaryTests {
    @Test func summaryNamesTheMetricTheSpanAndTheHeadline() {
        let spoken = AskHealthChartSummary.spoken(
            title: "Heart rate",
            range: "day",
            headline: "72 bpm",
            values: []
        )
        #expect(spoken == "Heart rate for the day. 72 bpm")
    }

    @Test func summaryAddsTheLowAndHighWhenTheSeriesSpreads() {
        let spoken = AskHealthChartSummary.spoken(
            title: "Steps",
            range: "week",
            headline: "8,420 steps",
            values: [200, 8_420, 1_000]
        )
        #expect(spoken.hasPrefix("Steps for the week. 8,420 steps. "))
        #expect(spoken.localizedStandardContains("low"))
        #expect(spoken.localizedStandardContains("high"))
    }

    @Test func aFlatSeriesDoesNotRepeatTheSameExtreme() {
        let spoken = AskHealthChartSummary.spoken(
            title: "Steps",
            range: "day",
            headline: "20 steps",
            values: [20, 20]
        )
        #expect(spoken == "Steps for the day. 20 steps")
    }
}
