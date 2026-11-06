import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
import os

/// How long a kept reply may be, based on Markdown mode and the active model's context window.
///
/// Plain answers stay short for speech. Rich Markdown scales with the model: on-device uses a
/// slice of the smaller window; Private Cloud Compute uses a larger slice, or the person's
/// Private Cloud response-length cap when that is set.
///
/// Private Cloud Compute's `contextSize` is async and can throw, so a session reads it once
/// and reply checks reuse that window. Until a read succeeds, the window is 32,768 tokens.
enum AskReplyBudget {
    /// English-biased estimate when the model tokenizer is not consulted.
    static let charactersPerToken = 4

    /// Character cap used by ``AskGuide/acceptsReply(_:facts:rich:)`` and stream previews.
    static func characterLimit(rich: Bool = AskMarkdownSelection.isOn) -> Int {
        let live = liveWindow()
        return characterLimit(
            rich: rich,
            compute: live.compute,
            contextSize: live.contextSize,
            cloudMaximumResponseTokens: live.cloudMaximumResponseTokens
        )
    }

    /// Token cap for a kept reply. Also used as `maximumResponseTokens` when rich text is on.
    static func responseTokenLimit(rich: Bool = AskMarkdownSelection.isOn) -> Int {
        let live = liveWindow()
        return responseTokenLimit(
            rich: rich,
            compute: live.compute,
            contextSize: live.contextSize,
            cloudMaximumResponseTokens: live.cloudMaximumResponseTokens
        )
    }

    /// Generation cap for the next session. `nil` leaves the model's default room.
    ///
    /// Plain on-device turns stay uncapped here (the 600-character accept rule still applies).
    /// Rich turns always pass a cap. Private Cloud also honors the response-length picker.
    static func generationTokenLimit(rich: Bool = AskMarkdownSelection.isOn) -> Int? {
        let live = liveWindow()
        switch live.compute {
        case .onDevice:
            return rich
                ? responseTokenLimit(
                    rich: true,
                    compute: .onDevice,
                    contextSize: live.contextSize,
                    cloudMaximumResponseTokens: nil
                )
                : nil
        case .privateCloud:
            if let capped = live.cloudMaximumResponseTokens { return capped }
            return rich
                ? responseTokenLimit(
                    rich: true,
                    compute: .privateCloud,
                    contextSize: live.contextSize,
                    cloudMaximumResponseTokens: nil
                )
                : nil
        }
    }

    static func estimatedTokens(for text: String) -> Int {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard count > 0 else { return 0 }
        return (count + charactersPerToken - 1) / charactersPerToken
    }

    static func characterLimit(
        rich: Bool,
        compute: AskCompute,
        contextSize: Int,
        cloudMaximumResponseTokens: Int?
    ) -> Int {
        responseTokenLimit(
            rich: rich,
            compute: compute,
            contextSize: contextSize,
            cloudMaximumResponseTokens: cloudMaximumResponseTokens
        ) * charactersPerToken
    }

    static func responseTokenLimit(
        rich: Bool,
        compute: AskCompute,
        contextSize: Int,
        cloudMaximumResponseTokens: Int?
    ) -> Int {
        if !rich { return 150 }
        let window = max(contextSize, 1)
        switch compute {
        case .onDevice:
            // About an eighth of the on-device window, enough for lists/tables without crowding the prompt.
            return min(512, max(256, window / 8))
        case .privateCloud:
            if let capped = cloudMaximumResponseTokens {
                return max(256, capped)
            }
            // Automatic length: about a sixteenth of the 32k Private Cloud window.
            return min(2_048, max(512, window / 16))
        }
    }

#if ASK_FOUNDATION_MODELS
    /// Reads the Private Cloud window and keeps it for the sync budget checks.
    /// A failed read leaves the previous window in place.
    static func rememberPrivateCloudContextSize(_ cloud: PrivateCloudComputeLanguageModel) async -> Int {
        if let read = try? await cloud.contextSize, read > 0 {
            privateCloudContextSize.withLock { $0 = read }
            return read
        }
        return privateCloudContextSize.withLock { $0 }
    }
#endif

    private struct LiveWindow {
        var compute: AskCompute
        var contextSize: Int
        var cloudMaximumResponseTokens: Int?
    }

    /// Usual Private Cloud Compute window, used until a session reads `contextSize`.
    private static let privateCloudContextSize = OSAllocatedUnfairLock(initialState: 32_768)

    private static func liveWindow() -> LiveWindow {
#if !ASK_FOUNDATION_MODELS
        // No model here. Budget against the smaller on-device window. A live device uses the size it reports.
        return LiveWindow(compute: .onDevice, contextSize: 4_096, cloudMaximumResponseTokens: nil)
#else
        let onDevice = SystemLanguageModel.default
        let cloud = PrivateCloudComputeLanguageModel()
        let compute = AskComputeChoice.resolved(
            preferred: AskComputeSelection.current,
            onDevice: onDevice.isAvailable,
            cloud: cloud.isAvailable,
            online: AskNetwork.isOnline
        )
        switch compute {
        case .onDevice:
            return LiveWindow(
                compute: .onDevice,
                contextSize: onDevice.contextSize,
                cloudMaximumResponseTokens: nil
            )
        case .privateCloud:
            return LiveWindow(
                compute: .privateCloud,
                contextSize: privateCloudContextSize.withLock { $0 },
                cloudMaximumResponseTokens: AskCloudSettings.current.length.maximumResponseTokens
            )
        }
#endif
    }
}
