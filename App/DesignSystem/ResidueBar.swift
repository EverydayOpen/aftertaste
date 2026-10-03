import AftertasteCore
import SwiftUI

// docs/DESIGN.md §6.3. Lesson f: bars and labels are proportional and never truncate.

/// One proportional bar per app: a segment per class, width by bytes with a floor so small classes stay legible, a
/// violet lit edge on segments that are ticked. Labels never live inside segments: the legend under the bar carries
/// class and size, and wraps instead of truncating. Pure fills, ImageRenderer-safe.
struct ResidueBar: View {
    struct Segment: Identifiable {
        let kind: ResidueKind
        let bytes: UInt64
        let ticked: Bool
        /// How well `bytes` is known; the legend says "at least" or "size not measured" instead of a false number.
        var state: SizeState = .measured
        var id: String { kind.rawValue }
    }

    let segments: [Segment]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One segment per class present in the group, largest first. A class is ticked when any of its items is. The app
    /// bundle (uninstall-now) is a class like the others.
    static func segments(for group: ResidueGroup, ticked: Set<String>) -> [Segment] {
        ResidueKind.allCases.compactMap { kind -> Segment? in
            let items = group.items.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            let states = Set(items.map(\.sizeState))
            let state: SizeState = states == [.measured] ? .measured : (states == [.notMeasured] ? .notMeasured : .atLeast)
            return Segment(kind: kind, bytes: items.reduce(0) { $0 + $1.size }, ticked: items.contains { ticked.contains($0.id) }, state: state)
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.kind.rawValue < $1.kind.rawValue }
    }

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.bytes })
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { g in
                let gap: CGFloat = 3, minW: CGFloat = 24
                let free = max(0, g.size.width - gap * CGFloat(max(0, segments.count - 1)) - minW * CGFloat(segments.count))
                HStack(spacing: gap) {
                    ForEach(segments) { s in
                        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                        shape.fill(contrast == .increased ? AnyShapeStyle(Color.primary.opacity(0.12))
                                   : AnyShapeStyle(LinearGradient(colors: dark ? [Color(red: 0.165, green: 0.184, blue: 0.239), Color(red: 0.118, green: 0.133, blue: 0.188)]
                                                                                : [Color(red: 0.992, green: 0.988, blue: 1), Color(red: 0.937, green: 0.929, blue: 0.973)],
                                                                  startPoint: .top, endPoint: .bottom)))
                            .overlay(alignment: .top) {
                                // Increase Contrast has no violet edge (DESIGN §6.5): the stroke carries the state.
                                if contrast != .increased {
                                    Capsule().fill(s.ticked ? Brand.dusk : Color.white.opacity(dark ? 0.12 : 0.9)).frame(height: 2).padding(.horizontal, 4).padding(.top, 1)
                                }
                            }
                            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : dark ? 0.10 : 0.08), lineWidth: contrast == .increased ? 1 : 0.5))
                            .frame(width: minW + free * CGFloat(s.bytes) / CGFloat(total))
                    }
                }
                // The widths follow the bytes by class, never the ticks, so only a rescan re-lays them out (MOTION §3.2).
                .animation(Motion.spring(reduceMotion), value: segments.map(\.bytes))
            }
            .frame(height: 14)
            // The legend: every class named, so no segment needs a label it cannot fit.
            Text(legend)
                .font(.caption).foregroundStyle(.secondary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Residue by class: " + segments.map { "\($0.kind.displayName) \(Format.size($0.bytes, $0.state))\($0.ticked ? ", selected" : "")" }.joined(separator: ", "))
    }

    private var legend: String {
        segments.map { "\($0.kind.displayName) \(Format.size($0.bytes, $0.state))" }.joined(separator: " · ")
    }
}
