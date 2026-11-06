import AppIntents

// Sample-host Siri tools for the Ask Garage readings.
// These are App Intents. They are not Foundation Models `Tool` values and they are not `AskSkill`s.
// `ToolIntent` exists in the 27.3 SDK. The app target defines ASK_SAMPLE_SIRI_TOOLS for that SDK.
// tvOS and watchOS stay ordinary App Intents. The tools only read `GarageSiriWork`.

nonisolated struct ReadGarageChargeIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Read Charge Status"
    nonisolated static let description = IntentDescription("Reports the Ask Garage sample car's battery, charge rate, plug, and charge limit.")

    nonisolated init() {}

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = await MainActor.run { GarageSiriWork.chargeStatus() }
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

nonisolated struct ReadGarageRangeIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Read Driving Range"
    nonisolated static let description = IntentDescription("Reports how far the Ask Garage sample car can still drive.")

    nonisolated init() {}

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = await MainActor.run { GarageSiriWork.drivingRange() }
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

nonisolated struct ReadGarageChargerIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Find Nearest Charger"
    nonisolated static let description = IntentDescription("Reports the nearest fast charger stored on the Ask Garage sample. It does not start directions.")

    nonisolated init() {}

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = await MainActor.run { GarageSiriWork.nearestCharger() }
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

nonisolated struct ReadGarageCabinIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Read Cabin Status"
    nonisolated static let description = IntentDescription("Reports the Ask Garage sample cabin temperature, departure, seat heat, and defrost. It does not change them.")

    nonisolated init() {}

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = await MainActor.run { GarageSiriWork.cabin() }
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

#if ASK_SAMPLE_SIRI_TOOLS && (os(iOS) || os(macOS) || os(visionOS))
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ReadGarageChargeIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ReadGarageRangeIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ReadGarageChargerIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ReadGarageCabinIntent: ToolIntent {}
#endif
