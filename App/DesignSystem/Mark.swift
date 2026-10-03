import SwiftUI

// docs/DESIGN.md §6.4, §7: the mark is a dashed rounded-square outline with a small solid tile lifted off its top-right
// corner (the app that left, and the tile that went with it). One drawing for the menu bar glyph, the card's back and
// the card.

/// The mark, in a 16 x 16 grid scaled to `size`. A flat `color`; template-friendly (the menu bar glyph is this in black).
struct AftertasteMark: View {
    var size: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 16
            let outline = Path(roundedRect: CGRect(x: 1.5 * k, y: 2.5 * k, width: 11 * k, height: 11 * k),
                               cornerSize: CGSize(width: 3 * k, height: 3 * k))
            ctx.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: 1.5 * k, dash: [3 * k, 2 * k]))   // the outline
            ctx.fill(Path(roundedRect: CGRect(x: 10.5 * k, y: 0.5 * k, width: 4.5 * k, height: 4.5 * k),
                          cornerSize: CGSize(width: 1.2 * k, height: 1.2 * k)), with: .color(color))                 // the tile that left
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The back of the Trace Report card while it is dealt (MOTION §3.3): the night sky, the horizon and the mark, no text,
/// so there is nothing to read or miss while it turns. Fixed night colours in both schemes. It fills whatever it is
/// laid over.
struct CardBack: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.skyTop, Brand.cardBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { g in
                Rectangle().fill(Brand.horizon.opacity(0.7)).frame(height: 1).offset(y: g.size.height * 0.82)
            }
            AftertasteMark(size: 56, color: Brand.cardAccent)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}
