import AftertasteCore
import SwiftUI

// docs/DESIGN.md §6: the afterglow wash, porcelain surfaces, wells, the lifted object, and the small display parts.
// Tirekick's recipes with the violet-black ink. Pure fills and strokes, so ImageRenderer-safe.

/// The afterglow behind stage screens (welcome, the result sheet, Erase readiness, the Trace Report): the plain window
/// plus the sky along the top edge, as a static wash that is gone well before any content starts. It never draws a
/// line: a hairline at a fixed height crossed text on every screen whose layout differs (first CI screenshots), so the
/// horizon is opt-in, for a caller that has reserved clear space for it (`horizon:` = the line's y from the top).
/// Increase Contrast gets the plain window. Drawn once per size.
struct Dawn: View {
    var strength = 1.0
    var horizon: CGFloat? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            if contrast != .increased {
                VStack(spacing: 0) {
                    // Violet to teal, fading into the window: the sky before sunrise, or by day at a fraction of the strength.
                    LinearGradient(colors: [Brand.skyTop.opacity((dark ? 0.9 : 0.12) * strength), Brand.skyLow.opacity((dark ? 0.7 : 0.14) * strength), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 200)
                    Spacer(minLength: 0)
                }
                if let horizon {
                    // Horizon draws its line through the middle of a 0.32 x width frame, so the offset is y minus half of that.
                    Horizon(tint: Brand.horizon, width: 440, soft: true).opacity(0.6 * strength).offset(y: horizon - 440 * 0.16)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private let sidebarFill = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.075, green: 0.075, blue: 0.082, alpha: 1)
        : NSColor(srgbRed: 0.925, green: 0.925, blue: 0.937, alpha: 1)
})

extension View {
    /// A symbol in a recessed, tinted squircle: the site's icon well. Pure fills, so ImageRenderer-safe.
    func well(_ tint: Color, size: CGFloat = 44) -> some View {
        modifier(Well(tint: tint, size: size))
    }

    /// A raised object (the card preview, the drop zone's tile; never a row): a tight contact shadow plus a wide soft
    /// one. compositingGroup so glyphs don't cast their own shadows (MOTION §1.4).
    func lifted() -> some View {
        compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.20), radius: 24, y: 14)
    }

    /// One flat fill for the whole sidebar column, under the traffic lights too. The List's own background is a material
    /// that stops at the toolbar, which left a white band over a grey list (first CI screenshots). `background(_:)` with
    /// a colour extends under the safe area. Apply to the sidebar's List. VERIFY by eye on the CI capture, light and dark.
    func sidebarSurface() -> some View {
        scrollContentBackground(.hidden).background(sidebarFill)
    }

    /// Evidence lines: a recessed well. The text stays primary and selectable.
    func terminal() -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return background(Color.primary.opacity(0.04), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// Porcelain surface: white (a 5.5% white lift in dark), a hairline rim, a tight contact shadow plus a wide soft
    /// one tinted with the brand ink. Concentric: pass the outer radius; content inside pads by radius - inner.
    /// Replaces grey grouped Form cells and `.quaternary` slabs. Never glass, never on a single row.
    func surface(_ radius: CGFloat = 16) -> some View { modifier(Surface(radius: radius)) }
}

private struct Surface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark, strong = contrast == .increased
        // The shadows hang off the fill, not the content: glyphs never cast their own (MOTION §1.4), and AppKit-backed
        // controls inside need no compositing group. White, not `.background`, which is the window's grey on macOS.
        // Dark's 5.5% fill casts almost nothing, so there the rim draws the edge (DESIGN §1.1 rule 3).
        return content
            .background {
                shape.fill(dark ? Color.white.opacity(0.055) : Color.white)
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.05), radius: 1, y: 1)
                    .shadow(color: Brand.ink.opacity(dark ? 0.5 : 0.10), radius: 16, y: 8)
            }
            .overlay {
                shape.strokeBorder(strong ? Color.primary.opacity(0.5) : Color.primary.opacity(dark ? 0.10 : 0.07), lineWidth: strong ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// Increase Contrast draws a 1pt primary edge.
private struct Well: ViewModifier {
    let tint: Color
    let size: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let increased = contrast == .increased
        return content
            .frame(width: size, height: size)
            // The inner shadow is what makes it read as recessed (ShapeStyle.shadow is macOS 13).
            .background(shape.fill(tint.opacity(0.16).gradient.shadow(.inner(color: .black.opacity(0.22), radius: 1.5, y: 1))))
            .overlay(shape.strokeBorder(increased ? Color.primary : tint.opacity(0.24), lineWidth: increased ? 1 : 0.5))
    }
}

/// An object standing on a glossy floor: the view, its mirror fading out over 45% of its height, and a still contact
/// shadow at its base. Drawn once. Pass a stateless view: it is drawn twice. No mirror under Reduce Transparency.
struct OnFloor<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let mirror = reduceTransparency ? 0 : height * 0.45
        VStack(spacing: 2) {
            content
                .background(alignment: .bottom) {
                    Ellipse().fill(.black.opacity(0.16)).frame(width: height * 0.7, height: height * 0.08).blur(radius: 6)
                        .offset(y: height * 0.04)   // centred on the base line. VERIFY by eye under an app icon
                        .accessibilityHidden(true)
                }
            if !reduceTransparency {
                content
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: mirror, alignment: .top).clipped()
                    .mask { LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // Pinned: on CI the mirror collapsed to 0pt and the old negative padding pulled the next view over the object's base.
        .frame(height: height + 2 + mirror, alignment: .top)
    }
}

/// The key light under a lifted object: a pool of light and a thin bright line. Static; drawn once per size.
/// `soft`: the dawn bloom. A hard line with a tight spill when false. Decorative, hidden from VoiceOver. The line runs
/// through the middle of the view's height.
struct Horizon: View {
    var tint: Color
    var width: CGFloat = 420
    var soft = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if contrast != .increased {
                // Elliptical, so the pool fades out inside its wide, short frame instead of being cut at the edges.
                EllipticalGradient(colors: [tint.opacity(soft ? 0.42 : 0.22), tint.opacity(soft ? 0.10 : 0), .clear],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            }
            LinearGradient(colors: [.clear, tint, .white.opacity(0.9), tint, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.86, height: 1)
        }
        .frame(width: width, height: width * (soft ? 0.32 : 0.14))   // the same with or without the pool
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small-caps label over a big number. One VoiceOver element. Sizes and counts are rounded; mono is for paths only.
struct Metric: View {
    let label: String
    let value: String
    var unit: String? = nil
    var dot: Color? = nil
    var design: Font.Design = .rounded
    var size: CGFloat = 26

    init(label: String, value: String, unit: String? = nil, dot: Color? = nil, design: Font.Design = .rounded, size: CGFloat = 26) {
        self.label = label
        self.value = value
        self.unit = unit
        self.dot = dot
        self.design = design
        self.size = size
    }

    /// `Metric("Found", "3.4", unit: "GB")`; `size: 40` for the preview's first value.
    init(_ label: String, _ value: String, unit: String? = nil, dot: Color? = nil, design: Font.Design = .rounded, size: CGFloat = 26) {
        self.init(label: label, value: value, unit: unit, dot: dot, design: design, size: size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(value).font(.system(size: size, weight: .semibold, design: design)).monospacedDigit()
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A count or a word in a tinted capsule. Colour sits in the dot and the fill; the text stays primary, so it always has
/// full contrast ("only symbols carry colour"). Increase Contrast adds a stroke. The tier chip is
/// `Tag(item.tier.displayName, tint: item.tier.tint)`.
struct Tag: View {
    let text: String
    var tint: Color = .secondary
    /// The sidebar's size: tighter padding and dot, so three tier chips fit one line.
    var compact = false
    @Environment(\.colorSchemeContrast) private var contrast

    init(text: String, tint: Color = .secondary, compact: Bool = false) {
        self.text = text
        self.tint = tint
        self.compact = compact
    }

    init(_ text: String, tint: Color = .secondary, compact: Bool = false) {
        self.init(text: text, tint: tint, compact: compact)
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Circle().fill(tint).frame(width: compact ? 5 : 6, height: compact ? 5 : 6).accessibilityHidden(true)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(contrast == .increased ? Color.primary.opacity(0.4) : tint.opacity(0.3), lineWidth: contrast == .increased ? 1 : 0.5))
    }
}

/// Wraps its children onto as many lines as the offered width needs, left to right. Unlike `ViewThatFits` over an
/// HStack and a VStack it fills a line before starting the next, so three tier chips take one line or two, never three.
/// With no width offered it lays everything on one line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(bounds.width, subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat?, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let limit = width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: widest, height: subviews.isEmpty ? 0 : y + lineHeight), origins)
    }
}

/// A sidebar row's tier chips: "2 High", "5 Medium", "1 Review", only the tiers that have items, in a wrapping flow.
/// The word is in the chip; only High has the violet dot (`Tier.tint`).
struct TierChips: View {
    let group: ResidueGroup

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach([Tier.high, .medium, .low], id: \.self) { tier in
                if group.count(tier) > 0 { Tag(text: "\(group.count(tier)) \(tier.displayName)", tint: tier.tint, compact: true) }
            }
        }
    }
}

/// A sheet's first lines: the action's symbol in a violet well, the title, one sentence.
struct SheetHeader: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Brand.duskInk)
                .well(Brand.dusk, size: 48).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(.title2.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
