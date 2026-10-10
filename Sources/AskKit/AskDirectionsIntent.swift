import AppIntents
import CoreLocation
import MapKit
import UIKit

public enum AskDirectionsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable:
            "Directions aren't available for that place."
        }
    }
}

/// Opens Maps with directions to one place. The location card button runs this. It is not an extra Siri phrase.
public struct OpenAskDirectionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Directions"
    public static let description = IntentDescription("Opens directions to a place in Maps.")

    /// Starts in the background. Maps will not open from a shortcut over the Home Screen, so this can continue in the foreground.
    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Place")
    public var place: String

    @Parameter(title: "Latitude")
    public var latitude: Double

    @Parameter(title: "Longitude")
    public var longitude: Double

    public static var parameterSummary: some ParameterSummary {
        Summary("Get directions to \(\.$place)")
    }

    public init() {}

    public init(place: String, latitude: Double, longitude: Double) {
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await askOpenDirections(
            place: place,
            latitude: latitude,
            longitude: longitude,
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening directions in Maps.", alwaysConfirm: false)
        }
        return .result(dialog: "Directions to \(name).")
    }
}

/// The directions button on a location card. A result dialog would open a second shortcut window on top of the snippet.
struct AskDirectionsTap: AppIntent {
    static let title: LocalizedStringResource = "Get Directions"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Place")
    var place: String

    @Parameter(title: "Latitude")
    var latitude: Double

    @Parameter(title: "Longitude")
    var longitude: Double

    init() {}

    init(place: String, latitude: Double, longitude: Double) {
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
    }

    func perform() async throws -> some IntentResult {
        _ = try await askOpenDirections(
            place: place,
            latitude: latitude,
            longitude: longitude,
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening directions in Maps.", alwaysConfirm: false)
        }
        return .result()
    }
}

private func askOpenDirections(
    place: String,
    latitude: Double,
    longitude: Double,
    canContinue: Bool,
    resumeInForeground: () async throws -> Void
) async throws -> String {
    let name = place.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
          (-90...90).contains(latitude),
          (-180...180).contains(longitude) else {
        throw AskDirectionsIntentError.unavailable
    }
    if await AskDirectionsOpen.open(name: name, latitude: latitude, longitude: longitude) {
        return name
    }
    // A shortcut over the Home Screen has no foreground scene, so Maps ignores the first open.
    guard canContinue else { throw AskDirectionsIntentError.unavailable }
    try await resumeInForeground()
    guard await AskDirectionsOpen.open(name: name, latitude: latitude, longitude: longitude) else {
        throw AskDirectionsIntentError.unavailable
    }
    return name
}

enum AskDirectionsOpen {
    @MainActor
    static func open(name: String, latitude: Double, longitude: Double) async -> Bool {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = name
        let options: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ]
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        if let scene {
            return await withCheckedContinuation { continuation in
                item.openInMaps(launchOptions: options, from: scene) { success in
                    continuation.resume(returning: success)
                }
            }
        }
        return item.openInMaps(launchOptions: options)
    }
}
