import AskKitConfiguration
import Configuration
import Foundation
import Testing

@Suite("Library configuration")
struct AskLibraryConfigurationTests {
    @Test func anEmptyReaderKeepsTheInitializerDefaults() {
        let flags = read([:])
        #expect(flags == .standard)
        #expect(flags.suppliedKeys.isEmpty)
        #expect(flags.webMetadata == false)
        #expect(flags.passesGeneratedFollowUpContext == false)
        #expect(flags.allowModel == true)
        #expect(flags.stream == false)
        #expect(flags.markdown == false)
        #expect(flags.workedTrace == true)
        #expect(flags.compute == .onDevice)
        #expect(flags.cloud.reasoning == .light)
        #expect(flags.cloud.temperature == nil)
        #expect(flags.cloud.length == .automatic)
        #expect(flags.appleSources.isEmpty)
        #expect(flags.appearance.placeholder == "Ask")
        #expect(flags.appearance.emptyMessage == "Ask a question, or start with a suggestion.")
        #expect(flags.appearance.thinkingTitle == "Thinking")
        #expect(flags.appearance.showsMicrophone == true)
        #expect(flags.appearance.title == nil)
        #expect(flags.appearance.composerSymbol == "sparkles")
    }

    @Test(arguments: flagSamples)
    func flagsFollowTheProviderWithoutChangingTheReader(_ sample: FlagSample) {
        let flags = read([
            "stream": bool(sample.stream),
            "markdown": bool(sample.markdown),
            "workedTrace": bool(sample.workedTrace),
            "allowModel": bool(sample.allowModel),
            "webMetadata": bool(sample.webMetadata),
            "compute": .init(.string(sample.compute.rawValue), isSecret: false),
        ])
        #expect(flags.stream == sample.stream)
        #expect(flags.markdown == sample.markdown)
        #expect(flags.workedTrace == sample.workedTrace)
        #expect(flags.allowModel == sample.allowModel)
        #expect(flags.webMetadata == sample.webMetadata)
        #expect(flags.compute == sample.compute)
        #expect(flags.suppliedKeys.contains(.stream))
        #expect(flags.suppliedKeys.contains(.compute))
        #expect(!flags.suppliedKeys.contains(.placeholder))
    }

    @Test func anEarlierProviderOverridesALaterOne() {
        let flags = AskLibraryConfiguration(
            config: ConfigReader(providers: [
                InMemoryProvider(values: [
                    "stream": true,
                    "compute": "privateCloud",
                    "cloud.temperature": 0.2,
                ]),
                InMemoryProvider(values: [
                    "stream": false,
                    "markdown": true,
                    "compute": "onDevice",
                    "cloud.temperature": 0.8,
                    "cloud.reasoning": "deep",
                ]),
            ])
        )
        #expect(flags.stream == true)
        #expect(flags.compute == .privateCloud)
        #expect(flags.cloud.temperature == 0.2)
        #expect(flags.markdown == true)
        #expect(flags.cloud.reasoning == .deep)
        #expect(flags.workedTrace == true)
        #expect(!flags.suppliedKeys.contains(.workedTrace))
    }

    @Test func theHostScopeHidesAnotherLibrary() {
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "askkit.webMetadata": true,
            "askkit.appearance.placeholder": "Ask the pantry",
            "other.webMetadata": false,
        ]))
        let ask = AskLibraryConfiguration(config: reader.scoped(to: "askkit"))
        let other = AskLibraryConfiguration(config: reader.scoped(to: "other"))
        #expect(ask.webMetadata == true)
        #expect(ask.appearance.placeholder == "Ask the pantry")
        #expect(other.webMetadata == false)
        #expect(other.suppliedKeys.contains(.webMetadata))
        #expect(other.appearance.placeholder == "Ask")
        #expect(!other.suppliedKeys.contains(.placeholder))
    }

    @Test func aWrongTypeOrUnknownNameStaysOnTheDefault() {
        let flags = read([
            "compute": "cloud",
            "workedTrace": "yes",
            "cloud.temperature": 1.5,
            "appleAccess": ConfigValue(.stringArray(["Weather", "nope", "calendar", "calendar"]), isSecret: false),
            "appearance.title": "",
        ])
        #expect(flags.compute == .onDevice)
        #expect(!flags.suppliedKeys.contains(.compute))
        #expect(flags.workedTrace == true)
        #expect(!flags.suppliedKeys.contains(.workedTrace))
        #expect(flags.cloud.temperature == nil)
        #expect(flags.suppliedKeys.contains(.cloudTemperature))
        #expect(flags.appleSources == [.weather, .calendar])
        #expect(flags.appearance.title == nil)
        #expect(flags.suppliedKeys.contains(.title))
    }

    @Test func aRemoteDocumentOverridesDefaultsAndMemoryOverridesTheDocument() throws {
        let document = Data("""
        {
          "webMetadata": true,
          "markdown": false,
          "cloud": { "reasoning": "deep", "temperature": 0, "length": "short" },
          "appleAccess": ["music", "weather"],
          "appearance": { "thinkingTitle": "Looking", "showsMicrophone": false },
          "kill": { "stream": false }
        }
        """.utf8)
        let remote = try AskRemoteJSONProvider(data: document)
        let defaults = InMemoryProvider(values: [
            "webMetadata": false,
            "markdown": true,
            "stream": true,
        ])
        let fromRemote = AskLibraryConfiguration(config: ConfigReader(providers: [remote, defaults]))
        #expect(fromRemote.webMetadata == true)
        #expect(fromRemote.markdown == false)
        #expect(fromRemote.stream == true)
        #expect(fromRemote.suppliedKeys.contains(.stream))
        #expect(fromRemote.cloud.reasoning == .deep)
        #expect(fromRemote.cloud.temperature == 0)
        #expect(fromRemote.cloud.length == .short)
        #expect(fromRemote.appleSources == [.music, .weather])
        #expect(fromRemote.appearance.thinkingTitle == "Looking")
        #expect(fromRemote.appearance.showsMicrophone == false)

        let overridden = AskLibraryConfiguration(config: ConfigReader(providers: [
            InMemoryProvider(values: ["markdown": true, "cloud.reasoning": "light"]),
            remote,
        ]))
        #expect(overridden.markdown == true)
        #expect(overridden.cloud.reasoning == .light)
        #expect(overridden.webMetadata == true)
    }

    @Test func aDottedNameMatchesANestedObject() throws {
        let nested = try AskRemoteJSONProvider(data: Data(#"{"cloud": {"length": "long"}}"#.utf8))
        let dotted = try AskRemoteJSONProvider(data: Data(#"{"cloud.length": "long"}"#.utf8))
        let fromNested = AskLibraryConfiguration(config: ConfigReader(provider: nested))
        let fromDotted = AskLibraryConfiguration(config: ConfigReader(provider: dotted))
        #expect(fromNested.cloud.length == .long)
        #expect(fromDotted.cloud.length == .long)
    }

    @Test func theProviderRejectsADocumentThatIsNotAnObject() {
        #expect(throws: AskRemoteJSONError.self) {
            try AskRemoteJSONProvider(data: Data("[]".utf8))
        }
        #expect(throws: AskRemoteJSONError.self) {
            try AskRemoteJSONProvider(data: Data("not json".utf8))
        }
        #expect(throws: AskRemoteJSONError.self) {
            try AskRemoteJSONProvider(data: Data(#"{"cloud.length": "long", "cloud": {"length": "short"}}"#.utf8))
        }
    }

    @Test func aBoolStaysABoolWhenTheDocumentIsJSON() throws {
        let provider = try AskRemoteJSONProvider(data: Data(#"{"markdown": true, "cloud": {"temperature": 0.25}}"#.utf8))
        let reader = ConfigReader(provider: provider)
        #expect(reader.bool(forKey: "markdown") == true)
        #expect(reader.string(forKey: "markdown") == nil)
        #expect(reader.double(forKey: "cloud.temperature") == 0.25)
    }
}

struct FlagSample: Sendable {
    var stream: Bool
    var markdown: Bool
    var workedTrace: Bool
    var allowModel: Bool
    var webMetadata: Bool
    var compute: AskConfiguredCompute
}

private let flagSamples = [
    FlagSample(
        stream: false,
        markdown: false,
        workedTrace: true,
        allowModel: true,
        webMetadata: false,
        compute: .onDevice
    ),
    FlagSample(
        stream: true,
        markdown: true,
        workedTrace: false,
        allowModel: false,
        webMetadata: true,
        compute: .privateCloud
    ),
]

private func read(_ values: [AbsoluteConfigKey: ConfigValue]) -> AskLibraryConfiguration {
    AskLibraryConfiguration(config: ConfigReader(provider: InMemoryProvider(values: values)))
}

private func bool(_ value: Bool) -> ConfigValue {
    ConfigValue(.bool(value), isSecret: false)
}
