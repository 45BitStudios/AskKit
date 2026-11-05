#if ASK_FOUNDATION_MODELS
import FoundationModels

/// A tool a skill or Apple source hands the model. The Foundation Models `Tool`.
public typealias AskTool = Tool
#else
/// The receptionist does not open a Foundation Models session on Apple TV or Apple Watch.
/// `AskOnDeviceResponder` can still call Private Cloud Compute on watchOS with a `Tool`.
/// The type keeps `AskModelClient` and skill signatures the same on every platform.
public protocol AskTool: Sendable {
    var name: String { get }
}
#endif
