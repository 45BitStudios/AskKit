import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if os(watchOS)
import WatchKit
#endif

#if canImport(UIKit)
/// The system image type on this platform.
package typealias AskPlatformImage = UIImage
#elseif canImport(AppKit)
/// The system image type on this platform.
package typealias AskPlatformImage = NSImage
#endif

/// The few places AskKit needs UIKit on one platform and AppKit or WatchKit on another.
package enum AskPlatform {
    /// True when the system has an SF Symbol with this name.
    package static func hasSymbol(_ name: String) -> Bool {
#if canImport(UIKit)
        UIImage(systemName: name) != nil
#elseif canImport(AppKit)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
#endif
    }

    /// PNG bytes for an image.
    package static func pngData(_ image: AskPlatformImage) -> Data? {
#if canImport(UIKit)
        image.pngData()
#elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
#endif
    }

    /// A CGImage for an image, for ImageIO and Vision.
    package static func cgImage(_ image: AskPlatformImage) -> CGImage? {
#if canImport(UIKit)
        image.cgImage
#elseif canImport(AppKit)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
#endif
    }

    /// Opens a URL outside the app. watchOS only opens `tel:` and `sms:` links.
    @MainActor
    @discardableResult
    package static func open(_ url: URL) async -> Bool {
#if os(watchOS)
        WKApplication.shared().openSystemURL(url)
        return true
#elseif canImport(UIKit)
        return await UIApplication.shared.open(url)
#elseif canImport(AppKit)
        return NSWorkspace.shared.open(url)
#endif
    }

    /// The fill behind a speech bubble and a card.
    @usableFromInline
    package static var bubbleFill: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .secondarySystemBackground)
#elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.2)
#endif
    }

    /// A light grouped fill, like a text field or a placeholder tile.
    package static var secondaryFill: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .secondarySystemFill)
#elseif os(macOS)
        Color(nsColor: .quaternaryLabelColor)
#else
        Color.gray.opacity(0.16)
#endif
    }

    /// Raised card surface. White in light mode, an elevated gray in dark mode.
    /// A host that wants this instead of the speech bubble assigns it to ``EnvironmentValues/askCardFill``.
    package static var cardFill: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .secondarySystemGroupedBackground)
#elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color.gray.opacity(0.14)
#endif
    }

    /// A lighter fill than ``secondaryFill``.
    package static var tertiaryFill: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .tertiarySystemFill)
#elseif os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.6)
#else
        Color.gray.opacity(0.1)
#endif
    }

    /// The screen or window background.
    package static var background: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .systemBackground)
#elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color.black
#endif
    }

    /// The grouped list background.
    package static var groupedBackground: Color {
#if os(iOS) || os(visionOS)
        Color(uiColor: .systemGroupedBackground)
#elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color.black
#endif
    }
}
