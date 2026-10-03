import AppKit
import SwiftUI

/// The optional menu bar item's glyph (docs/DESIGN.md §6.4), drawn once by `ImageRenderer` and cached: the mark as a
/// template image, so it follows the menu bar's appearance. No badge, no colour, no animation, ever: the item only
/// reopens the window.
@MainActor enum MenuBarIcon {
    // VERIFY on macOS 13, 15 and 26: Canvas renders through ImageRenderer. If it comes out blank, redraw the mark with
    // plain shapes.
    static let glyph: NSImage = {
        let renderer = ImageRenderer(content: AftertasteMark(size: 16, color: .black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()
}
