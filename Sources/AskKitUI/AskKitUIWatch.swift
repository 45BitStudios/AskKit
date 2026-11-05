#if os(watchOS)
/// The chat, cards, and trace viewer are left out of the watchOS build.
///
/// Those screens use SwiftUI that watchOS does not provide, including the principal
/// toolbar slot, menus, context menus, and pinch gestures. A watch app imports AskKit
/// and draws its own interface. `AskOnDeviceResponder` with `model: .privateCloud` is
/// the answer session.
public enum AskKitUIWatch {
    public static let isIncluded = false
}
#endif
