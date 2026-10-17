// Photos is not on Apple Watch, so this file builds empty there.
#if canImport(Photos)
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// The image type Photos hands back on this platform.
public typealias PhotoQueryImage = UIImage

extension UIImage {
    var photoQueryCGImage: CGImage? { cgImage }
}
#elseif canImport(AppKit)
import AppKit

/// The image type Photos hands back on this platform.
public typealias PhotoQueryImage = NSImage

extension NSImage {
    var photoQueryCGImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#endif
#endif
