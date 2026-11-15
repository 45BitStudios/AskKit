import AskKitConfiguration
import Foundation

extension AskConfiguration {
    /// Copies the feature flags ``AskLibraryConfiguration`` found in the reader.
    ///
    /// A key the reader does not contain stays as it is on this value.
    /// Skills, domains, tools, and closures stay as they are.
    /// Device toggles such as streaming and the model choice are applied with ``AskLibraryConfiguration/installDeviceFlags(into:)``.
    /// `allowModel` stays on ``AskLibraryConfiguration`` for the caller to pass into ``AskOnDeviceResponder``.
    public func applying(_ library: AskLibraryConfiguration) -> AskConfiguration {
        var copy = self
        if library.suppliedKeys.contains(.webMetadata) {
            copy.webMetadata = library.webMetadata
        }
        if library.suppliedKeys.contains(.passesGeneratedFollowUpContext) {
            copy.passesGeneratedFollowUpContext = library.passesGeneratedFollowUpContext
        }
        if library.suppliedKeys.contains(.appleAccess) {
            copy.appleAccess = library.appleAccess
        }
        return copy
    }
}

extension AskLibraryConfiguration {
    /// `appleAccess` as ``AskAppleAccess``. Unknown names were dropped while reading.
    ///
    /// A new ``AskConfiguredAppleSource`` case has to be added here. The compiler requires that update.
    public var appleAccess: AskAppleAccess {
        var access: AskAppleAccess = []
        for source in appleSources {
            switch source {
            case .calendar: access.insert(.calendar)
            case .reminders: access.insert(.reminders)
            case .contacts: access.insert(.contacts)
            case .location: access.insert(.location)
            case .health: access.insert(.health)
            case .music: access.insert(.music)
            case .weather: access.insert(.weather)
            case .alarms: access.insert(.alarms)
            }
        }
        return access
    }

    /// ``compute`` as ``AskCompute``.
    public var askCompute: AskCompute {
        switch compute {
        case .onDevice: .onDevice
        case .privateCloud: .privateCloud
        }
    }

    /// ``cloud`` as ``AskCloudOptions``.
    public var cloudOptions: AskCloudOptions {
        AskCloudOptions(
            reasoning: cloudReasoning,
            temperature: cloud.temperature,
            length: cloudLength
        )
    }

    private var cloudReasoning: AskCloudReasoning {
        switch cloud.reasoning {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        }
    }

    private var cloudLength: AskCloudLength {
        switch cloud.length {
        case .automatic: .automatic
        case .short: .short
        case .medium: .medium
        case .long: .long
        }
    }

    /// Writes the device toggles the reader contained into the `UserDefaults` keys AskKit already uses.
    ///
    /// Keys the reader left out are not written, so a partial document does not reset the rest.
    /// Skip this call and ``AskStreamSelection``, ``AskMarkdownSelection``, ``AskWorkedTraceSelection``,
    /// ``AskComputeSelection``, and ``AskCloudSettings`` keep their current behavior.
    public func installDeviceFlags(into defaults: UserDefaults = .standard) {
        if suppliedKeys.contains(.stream) {
            defaults.set(stream, forKey: AskStreamSelection.storageKey)
        }
        if suppliedKeys.contains(.markdown) {
            defaults.set(markdown, forKey: AskMarkdownSelection.storageKey)
        }
        if suppliedKeys.contains(.workedTrace) {
            defaults.set(workedTrace, forKey: AskWorkedTraceSelection.storageKey)
        }
        if suppliedKeys.contains(.compute) {
            if defaults === UserDefaults.standard {
                AskComputeSelection.current = askCompute
            } else {
                defaults.set(askCompute.rawValue, forKey: AskComputeSelection.storageKey)
            }
        }
        let cloudKeys: Set<AskLibraryKey> = [.cloudReasoning, .cloudTemperature, .cloudLength]
        guard !suppliedKeys.isDisjoint(with: cloudKeys) else { return }
        var options = defaults === UserDefaults.standard ? AskCloudSettings.current : AskCloudSettings.read(defaults)
        if suppliedKeys.contains(.cloudReasoning) {
            options.reasoning = cloudReasoning
        }
        if suppliedKeys.contains(.cloudLength) {
            options.length = cloudLength
        }
        if suppliedKeys.contains(.cloudTemperature) {
            options.temperature = cloud.temperature
        }
        if defaults === UserDefaults.standard {
            AskCloudSettings.current = options
        } else {
            AskCloudSettings.write(options, to: defaults)
        }
    }
}
