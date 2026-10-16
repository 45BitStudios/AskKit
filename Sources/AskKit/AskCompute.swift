import Foundation
import Network
import os

/// The Foundation Models backend for a turn: the on-device system model, or Private Cloud Compute.
///
/// ``AskPersistence/privateCloud(containerIdentifier:storeURL:)`` stores turns in CloudKit.
/// This choice only selects which model answers. It does not move the transcript.
public enum AskCompute: String, Sendable, CaseIterable, Hashable {
    case onDevice
    case privateCloud

    /// Short name shown on the composer capsule and in the model sheet.
    public var title: String {
        switch self {
        case .onDevice: "On-Device"
        case .privateCloud: "Private Cloud"
        }
    }

    /// Phone for the on-device model, cloud for Private Cloud Compute.
    var symbolName: String {
        switch self {
        case .onDevice: "iphone"
        case .privateCloud: "cloud"
        }
    }

    /// Spoken name. Private Cloud is announced as Private Cloud Compute.
    public var accessibilityLabel: String {
        switch self {
        case .onDevice: "On-Device"
        case .privateCloud: "Private Cloud Compute"
        }
    }
}

/// The model the person picked, remembered on this device.
///
/// The key is `AskKit.compute` in standard `UserDefaults`. It is not an app-group default.
/// A model that is briefly unavailable does not clear this value. The next session uses the
/// other model when that one is ready, and returns here when the saved model is ready again.
public enum AskComputeSelection: Sendable {
    public static let storageKey = "AskKit.compute"

    private static let lock = OSAllocatedUnfairLock()

    public static var current: AskCompute {
        get { lock.withLockUnchecked { stored } }
        set { lock.withLockUnchecked { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) } }
    }

    private static var stored: AskCompute {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let choice = AskCompute(rawValue: raw) else {
            return .onDevice
        }
        return choice
    }
}

/// Whether this device currently has a usable network path.
///
/// Private Cloud Compute needs the network. On-device turns ignore this.
enum AskNetwork {
    private static let lock = OSAllocatedUnfairLock(initialState: true)

    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "AskKit.network")
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            lock.withLock { $0 = online }
            Task { @MainActor in
                AskNetworkStatus.shared.apply(online)
            }
        }
        monitor.start(queue: queue)
        lock.withLock { $0 = monitor.currentPath.status == .satisfied }
        return monitor
    }()

    /// Satisfied path from `NWPathMonitor`. Starts the monitor on first read.
    static var isOnline: Bool {
        _ = monitor
        return lock.withLock { $0 }
    }
}

/// Path status the composer observes so the capsule can fall back while offline.
@MainActor
@Observable
final class AskNetworkStatus {
    static let shared = AskNetworkStatus()

    private(set) var isOnline = true

    /// Starts the path monitor and syncs the current value.
    func start() {
        isOnline = AskNetwork.isOnline
    }

    fileprivate func apply(_ online: Bool) {
        isOnline = online
    }
}

enum AskComputeChoice {
    /// Preferred model when that one is up. Otherwise the other model when it is up.
    /// Private Cloud also needs a network path. Both down returns the preference so the
    /// session reports the model's own error.
    static func resolved(preferred: AskCompute, onDevice: Bool, cloud: Bool, online: Bool) -> AskCompute {
        let cloudReady = cloud && online
        switch preferred {
        case .onDevice where onDevice:
            return .onDevice
        case .privateCloud where cloudReady:
            return .privateCloud
        case .onDevice where cloudReady:
            return .privateCloud
        case .privateCloud where onDevice:
            return .onDevice
        default:
            return preferred
        }
    }
}

/// How hard Private Cloud Compute thinks before it answers.
public enum AskCloudReasoning: String, Sendable, CaseIterable, Hashable {
    case light
    case moderate
    case deep

    public var title: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .deep: "Deep"
        }
    }

    public var detail: String {
        switch self {
        case .light: "A quicker answer."
        case .moderate: "A little more thought."
        case .deep: "A longer look before the answer."
        }
    }
}

/// How long a Private Cloud Compute answer is allowed to run.
public enum AskCloudLength: String, Sendable, CaseIterable, Hashable {
    case automatic
    case short
    case medium
    case long

    public var title: String {
        switch self {
        case .automatic: "Auto"
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        }
    }

    public var accessibilityLabel: String {
        self == .automatic ? "Automatic" : title
    }

    var maximumResponseTokens: Int? {
        switch self {
        case .automatic: nil
        case .short: 256
        case .medium: 512
        case .long: 1024
        }
    }
}

/// Reasoning, temperature, and response length for Private Cloud Compute.
public struct AskCloudOptions: Sendable, Equatable {
    public var reasoning: AskCloudReasoning
    /// `nil` leaves the model's own temperature. A set value is 0...1.
    public var temperature: Double?
    public var length: AskCloudLength

    public init(reasoning: AskCloudReasoning, temperature: Double?, length: AskCloudLength) {
        self.reasoning = reasoning
        self.temperature = temperature
        self.length = length
    }

    public static let standard = AskCloudOptions(reasoning: .light, temperature: nil, length: .automatic)
}

/// Private Cloud Compute options remembered on this device.
///
/// Keys live in standard `UserDefaults`: `AskKit.cloud.reasoning`, `AskKit.cloud.temperature`,
/// and `AskKit.cloud.length`. They are not app-group defaults. On-device turns ignore them.
public enum AskCloudSettings: Sendable {
    public static let reasoningKey = "AskKit.cloud.reasoning"
    public static let temperatureKey = "AskKit.cloud.temperature"
    public static let lengthKey = "AskKit.cloud.length"

    private static let lock = OSAllocatedUnfairLock()

    public static var current: AskCloudOptions {
        get { lock.withLockUnchecked { read(.standard) } }
        set { lock.withLockUnchecked { write(newValue, to: .standard) } }
    }

    static func read(_ defaults: UserDefaults) -> AskCloudOptions {
        let reasoning = AskCloudReasoning(rawValue: defaults.string(forKey: reasoningKey) ?? "") ?? .light
        let length = AskCloudLength(rawValue: defaults.string(forKey: lengthKey) ?? "") ?? .automatic
        let temperature = storedTemperature(defaults.object(forKey: temperatureKey))
        return AskCloudOptions(reasoning: reasoning, temperature: temperature, length: length)
    }

    static func write(_ options: AskCloudOptions, to defaults: UserDefaults) {
        defaults.set(options.reasoning.rawValue, forKey: reasoningKey)
        defaults.set(options.length.rawValue, forKey: lengthKey)
        if let temperature = storedTemperature(options.temperature) {
            defaults.set(temperature, forKey: temperatureKey)
        } else {
            defaults.removeObject(forKey: temperatureKey)
        }
    }

    private static func storedTemperature(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? Double {
            number = value
        } else if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = nil
        }
        guard let number, (0...1).contains(number) else { return nil }
        return number
    }
}

enum AskCloudQuotaText {
    static func line(reached: Bool, approaching: Bool) -> String {
        if reached { return "Daily limit reached" }
        if approaching { return "Near the daily limit" }
        return "Within the daily limit"
    }
}
