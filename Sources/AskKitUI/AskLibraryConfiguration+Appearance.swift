#if !os(watchOS)
import AskKitConfiguration

extension AskChatAppearance {
    /// Copies the chat strings and the microphone switch ``AskLibraryConfiguration`` found in the reader.
    ///
    /// A key the reader does not contain stays as it is on this value.
    /// Tint, bubbles, logos, and voice colors stay here. They are not config scalars.
    public func applying(_ library: AskLibraryConfiguration) -> AskChatAppearance {
        var copy = self
        let appearance = library.appearance
        if library.suppliedKeys.contains(.placeholder) {
            copy.placeholder = appearance.placeholder
        }
        if library.suppliedKeys.contains(.emptyMessage) {
            copy.emptyMessage = appearance.emptyMessage
        }
        if library.suppliedKeys.contains(.thinkingTitle) {
            copy.thinkingTitle = appearance.thinkingTitle
        }
        if library.suppliedKeys.contains(.showsMicrophone) {
            copy.showsMicrophone = appearance.showsMicrophone
        }
        if library.suppliedKeys.contains(.title) {
            copy.title = appearance.title
        }
        if library.suppliedKeys.contains(.emptyTitle) {
            copy.emptyTitle = appearance.emptyTitle
        }
        if library.suppliedKeys.contains(.composerSymbol) {
            copy.composerSymbol = appearance.composerSymbol
        }
        return copy
    }
}
#endif
