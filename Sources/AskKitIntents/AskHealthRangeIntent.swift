import AppIntents
import AskKit
import Charts
import Foundation
import SwiftUI

/// Shows one measurement for a day, week, month, or year. Siri and the Show Health shortcut run this and speak the result.
public struct ShowAskHealthRangeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Health Range"
    public static let description = IntentDescription("Shows a health measurement for a day, week, month, or year.")

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Measurement")
    public var measurement: AskHealthMeasurement

    @Parameter(title: "Range")
    public var range: AskHealthRange

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$measurement) for \(\.$range)")
    }

    public init() {}

    public init(measurement: AskHealthMeasurement, range: AskHealthRange) {
        self.measurement = measurement
        self.range = range
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let chosen = measurement
        let chosenRange = range
        let name = chosen.spokenName
        let period = chosenRange.spokenName
        await AskHealthRangeApply.select(metric: chosen.rawValue, range: chosenRange)
        return .result(dialog: "Showing \(name) for the \(period).")
    }
}

/// Day, Week, Month, and Year on the chart. A dialog would open a second shortcut window, so this only stores the choice and the snippet redraws.
package struct AskHealthRangeTap: AppIntent {
    package static let title: LocalizedStringResource = "Show Health Range"
    package static let isDiscoverable = false

    package static var supportedModes: IntentModes { .background }
    package static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Measurement")
    var measurement: AskHealthMeasurement

    @Parameter(title: "Range")
    var range: AskHealthRange

    package init() {}

    package init(measurement: AskHealthMeasurement, range: AskHealthRange) {
        self.measurement = measurement
        self.range = range
    }

    package func perform() async throws -> some IntentResult {
        let chosen = measurement
        let chosenRange = range
        await AskHealthRangeApply.select(metric: chosen.rawValue, range: chosenRange)
        return .result()
    }
}

private enum AskHealthRangeApply {
    static func select(metric: String, range: AskHealthRange) async {
        await MainActor.run {
            AskHealthRanges.shared.select(metric: metric, range: range)
        }
    }
}
