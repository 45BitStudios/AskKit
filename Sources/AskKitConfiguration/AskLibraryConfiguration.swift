import Configuration

/// Model choice stored under `compute`. The raw values match `AskCompute`.
public enum AskConfiguredCompute: String, Sendable, Hashable, CaseIterable {
    case onDevice
    case privateCloud
}

/// How hard Private Cloud Compute thinks. The raw values match `AskCloudReasoning`.
public enum AskConfiguredCloudReasoning: String, Sendable, Hashable, CaseIterable {
    case light
    case moderate
    case deep
}

/// How long a Private Cloud Compute answer may run. The raw values match `AskCloudLength`.
public enum AskConfiguredCloudLength: String, Sendable, Hashable, CaseIterable {
    case automatic
    case short
    case medium
    case long
}

/// Reasoning, temperature, and response length for Private Cloud Compute.
public struct AskConfiguredCloud: Sendable, Equatable {
    public var reasoning: AskConfiguredCloudReasoning
    /// `nil` leaves the model's own temperature. A set value is 0...1.
    public var temperature: Double?
    public var length: AskConfiguredCloudLength

    public init(
        reasoning: AskConfiguredCloudReasoning,
        temperature: Double?,
        length: AskConfiguredCloudLength
    ) {
        self.reasoning = reasoning
        self.temperature = temperature
        self.length = length
    }
}

/// Apple sources a reply may use. The raw values are the composer names.
public enum AskConfiguredAppleSource: String, Sendable, Hashable, CaseIterable {
    case calendar
    case reminders
    case contacts
    case location
    case health
    case music
    case weather
    case alarms
}

/// Chat copy and the microphone switch. Colors and logos stay on `AskChatAppearance`.
public struct AskConfiguredAppearance: Sendable, Equatable {
    public var placeholder: String
    public var emptyMessage: String
    public var thinkingTitle: String
    public var showsMicrophone: Bool
    /// Empty in the document clears a title a previous value had set.
    public var title: String?
    public var emptyTitle: String?
    public var composerSymbol: String

    public init(
        placeholder: String,
        emptyMessage: String,
        thinkingTitle: String,
        showsMicrophone: Bool,
        title: String?,
        emptyTitle: String?,
        composerSymbol: String
    ) {
        self.placeholder = placeholder
        self.emptyMessage = emptyMessage
        self.thinkingTitle = thinkingTitle
        self.showsMicrophone = showsMicrophone
        self.title = title
        self.emptyTitle = emptyTitle
        self.composerSymbol = composerSymbol
    }
}

/// Which library keys the reader actually contained.
///
/// `AskConfiguration.applying(_:)` and `AskChatAppearance.applying(_:)` change a field only when its key is in this set.
public enum AskLibraryKey: String, Sendable, Hashable, CaseIterable {
    case webMetadata
    case passesGeneratedFollowUpContext
    case allowModel
    case stream
    case markdown
    case workedTrace
    case compute
    case cloudReasoning
    case cloudTemperature
    case cloudLength
    case appleAccess
    case placeholder
    case emptyMessage
    case thinkingTitle
    case showsMicrophone
    case title
    case composerSymbol
    case emptyTitle
}

/// Feature flags, model options, and chat copy read from one `ConfigReader`.
///
/// This is the slice of AskKit a host can pass as configuration instead of another initializer argument or another `UserDefaults` key.
/// Skills, domains, tools, closures, and colors stay on the existing initializers.
///
/// The initializer reads once. A new flag document means a new value. The package dependency uses swift-configuration's default JSON trait and does not enable `Reloading`.
///
/// A host such as YouTubeActions builds one reader and scopes it for this library:
///
/// ```swift
/// let flags = AskLibraryConfiguration(config: reader.scoped(to: "askkit"))
/// ```
///
/// The library does not add that prefix. The host chooses the scope, which is the pattern in Apple's configuring-libraries guide.
public struct AskLibraryConfiguration: Sendable, Equatable {
    /// Reads the title and summary of an https address in the question. Off until a reader sets it.
    public var webMetadata: Bool
    /// When true, a later generated card's compose prompt includes earlier cards' facts.
    public var passesGeneratedFollowUpContext: Bool
    /// When false, `AskOnDeviceResponder` skips the model. The responder's own default is true.
    public var allowModel: Bool
    /// Answer text grows in the bubble while the model writes. Off until a reader sets it.
    public var stream: Bool
    /// Assistant bubbles may render Markdown. Off until a reader sets it.
    public var markdown: Bool
    /// Debug builds show the worked-trace pill. On when the key is missing, matching `AskWorkedTraceSelection`.
    public var workedTrace: Bool
    /// On-device model, or Private Cloud Compute.
    public var compute: AskConfiguredCompute
    public var cloud: AskConfiguredCloud
    /// Names the reader listed under `appleAccess`. Unknown names are dropped.
    public var appleSources: [AskConfiguredAppleSource]
    public var appearance: AskConfiguredAppearance
    /// Keys present on the reader. Missing keys keep ``standard`` and stay out of this set.
    public var suppliedKeys: Set<AskLibraryKey>

    /// The same values an empty reader produces.
    public static let standard = AskLibraryConfiguration()

    init() {
        webMetadata = false
        passesGeneratedFollowUpContext = false
        allowModel = true
        stream = false
        markdown = false
        workedTrace = true
        compute = .onDevice
        cloud = AskConfiguredCloud(reasoning: .light, temperature: nil, length: .automatic)
        appleSources = []
        appearance = AskConfiguredAppearance(
            placeholder: "Ask",
            emptyMessage: "Ask a question, or start with a suggestion.",
            thinkingTitle: "Thinking",
            showsMicrophone: true,
            title: nil,
            emptyTitle: nil,
            composerSymbol: "sparkles"
        )
        suppliedKeys = []
    }

    /// Reads this library's keys from `config`.
    ///
    /// Pass a reader the host has already scoped, usually with `scoped(to: "askkit")`.
    /// A missing key keeps the default below and is left out of ``suppliedKeys``.
    /// A value of the wrong type is treated as missing. `InMemoryProvider` does not coerce types, so a test stores a bool as a bool and a temperature as a double.
    ///
    /// ## Keys
    /// - `webMetadata` (bool, default false)
    /// - `passesGeneratedFollowUpContext` (bool, default false)
    /// - `allowModel` (bool, default true)
    /// - `stream` (bool, default false). Same meaning as `AskKit.stream`.
    /// - `markdown` (bool, default false). Same meaning as `AskKit.markdown`.
    /// - `workedTrace` (bool, default true). Same meaning as `AskKit.workedTrace`.
    /// - `compute` (`onDevice` or `privateCloud`, default `onDevice`)
    /// - `cloud.reasoning` (`light`, `moderate`, or `deep`, default `light`)
    /// - `cloud.temperature` (double from 0 through 1, default none). Outside that range is read as none.
    /// - `cloud.length` (`automatic`, `short`, `medium`, or `long`, default `automatic`)
    /// - `appleAccess` (string array, default empty). `calendar`, `reminders`, `contacts`, `location`, `health`, `music`, `weather`, `alarms`. Any other name is dropped.
    /// - `appearance.placeholder` (string, default `Ask`)
    /// - `appearance.emptyMessage` (string, default `Ask a question, or start with a suggestion.`)
    /// - `appearance.thinkingTitle` (string, default `Thinking`)
    /// - `appearance.showsMicrophone` (bool, default true)
    /// - `appearance.title` (string, default none). An empty string clears it.
    /// - `appearance.emptyTitle` (string, default none). An empty string clears it.
    /// - `appearance.composerSymbol` (string, default `sparkles`)
    public init(config: ConfigReader) {
        self.init()
        take(.webMetadata, config.bool(forKey: "webMetadata"), \.webMetadata)
        take(
            .passesGeneratedFollowUpContext,
            config.bool(forKey: "passesGeneratedFollowUpContext"),
            \.passesGeneratedFollowUpContext
        )
        take(.allowModel, config.bool(forKey: "allowModel"), \.allowModel)
        take(.stream, config.bool(forKey: "stream"), \.stream)
        take(.markdown, config.bool(forKey: "markdown"), \.markdown)
        take(.workedTrace, config.bool(forKey: "workedTrace"), \.workedTrace)
        take(.compute, config.string(forKey: "compute", as: AskConfiguredCompute.self), \.compute)
        take(
            .cloudReasoning,
            config.string(forKey: "cloud.reasoning", as: AskConfiguredCloudReasoning.self),
            \.cloud.reasoning
        )
        if let temperature = config.double(forKey: "cloud.temperature") {
            suppliedKeys.insert(.cloudTemperature)
            cloud.temperature = (0...1).contains(temperature) ? temperature : nil
        }
        take(
            .cloudLength,
            config.string(forKey: "cloud.length", as: AskConfiguredCloudLength.self),
            \.cloud.length
        )
        if let names = config.stringArray(forKey: "appleAccess") {
            suppliedKeys.insert(.appleAccess)
            var seen = Set<AskConfiguredAppleSource>()
            appleSources = names.compactMap { AskConfiguredAppleSource(rawValue: $0.lowercased()) }
                .filter { seen.insert($0).inserted }
        }
        take(.placeholder, config.string(forKey: "appearance.placeholder"), \.appearance.placeholder)
        take(.emptyMessage, config.string(forKey: "appearance.emptyMessage"), \.appearance.emptyMessage)
        take(.thinkingTitle, config.string(forKey: "appearance.thinkingTitle"), \.appearance.thinkingTitle)
        take(.showsMicrophone, config.bool(forKey: "appearance.showsMicrophone"), \.appearance.showsMicrophone)
        if let title = config.string(forKey: "appearance.title") {
            suppliedKeys.insert(.title)
            appearance.title = title.isEmpty ? nil : title
        }
        if let emptyTitle = config.string(forKey: "appearance.emptyTitle") {
            suppliedKeys.insert(.emptyTitle)
            appearance.emptyTitle = emptyTitle.isEmpty ? nil : emptyTitle
        }
        take(.composerSymbol, config.string(forKey: "appearance.composerSymbol"), \.appearance.composerSymbol)
    }

    private mutating func take<Value>(
        _ key: AskLibraryKey,
        _ value: Value?,
        _ keyPath: WritableKeyPath<AskLibraryConfiguration, Value>
    ) {
        guard let value else { return }
        self[keyPath: keyPath] = value
        suppliedKeys.insert(key)
    }
}
