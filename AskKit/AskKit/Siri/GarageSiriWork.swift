import Foundation

/// Readings the Ask Garage sample already shows in chat.
///
/// These are not Foundation Models tools and they do not change the car.
/// Siri tools in this app call these functions so the spoken line cannot drift from `GarageSample`.
enum GarageSiriWork {
    static let notGarage = "Ask Garage is not the sample open in the app. Switch to Ask Garage in the app to read the car. This does not invent a battery, a range, or a charger."

    static func chargeStatus() -> String {
        guard SampleProject.selected == .garage else { return notGarage }
        return "The \(GarageSample.vehicle) battery is at \(GarageSample.battery). It is plugged in at home, charging at \(GarageSample.chargeRate). About \(GarageSample.minutesTo80) minutes until 80 percent. The charge limit is \(GarageSample.chargeLimit)."
    }

    static func drivingRange() -> String {
        guard SampleProject.selected == .garage else { return notGarage }
        return "Range is \(GarageSample.range)."
    }

    static func nearestCharger() -> String {
        guard SampleProject.selected == .garage else { return notGarage }
        return "The nearest fast charger in this sample is \(GarageSample.chargerName), \(GarageSample.chargerDistance) away, with \(GarageSample.openStalls) stalls open. This does not start directions."
    }

    static func cabin() -> String {
        guard SampleProject.selected == .garage else { return notGarage }
        return "The cabin will be \(GarageSample.cabin) by \(GarageSample.departure). Driver seat heat is \(GarageSample.seatHeat). Front defrost is \(GarageSample.defrost). This does not change the car."
    }
}
