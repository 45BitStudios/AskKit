#if ASK_FOUNDATION_MODELS
import FoundationModels

/// A tool a skill or Apple source hands the model. The Foundation Models `Tool`.
public typealias AskTool = Tool
#else
/// Foundation Models does not run on Apple TV or Apple Watch, so no tool reaches a model here.
/// The type keeps `AskModelClient` and skill signatures the same on every platform.
public protocol AskTool: Sendable {
    var name: String { get }
}
#endif
